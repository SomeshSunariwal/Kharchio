"""Export portable Whisper Small DLCs locally using Qualcomm's graph adaptation.

Requires torch 2.8, transformers 4.57, onnx, and the QAIRT converter dependencies.
No cloud compilation or user audio is involved. Downloads are development-only.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / ".tmp/qnn-export"
QAIRT = ROOT / "native/prebuilt/qairt/qairt/2.50.0.260828"
REFERENCE_REVISION = "1c23e6d6c6ab2e6edbfb671c07484855d2e2511b"
CHECKPOINT_REVISION = "973afd24965f72e36ca33b3055d56a652f456b4d"


def download(url, target):
    if target.exists():
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_suffix(target.suffix + ".partial")
    with urllib.request.urlopen(url) as source, partial.open("wb") as output:
        shutil.copyfileobj(source, output)
    partial.replace(target)


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def main():
    sys.path.insert(0, str(WORK / "deps"))
    reference = WORK / "reference"
    for name in ("models/templates/hf_whisper/model_adaptation.py", "utils/model_adapters.py", "utils/torch_typing_helpers.py"):
        download(f"https://raw.githubusercontent.com/qualcomm/ai-hub-models/{REFERENCE_REVISION}/src/qai_hub_models/{name}",
                 reference / "qai_hub_models" / name)
    sys.path.insert(0, str(reference))
    checkpoint = WORK / "checkpoint"
    for name in ("config.json", "generation_config.json", "model.safetensors"):
        download(f"https://huggingface.co/openai/whisper-small/resolve/{CHECKPOINT_REVISION}/{name}", checkpoint / name)

    import torch
    from transformers import WhisperForConditionalGeneration
    from qai_hub_models.models.templates.hf_whisper.model_adaptation import monkey_patch_model

    torch.set_num_threads(4)
    print("Loading and adapting multilingual Whisper Small", flush=True)
    model = WhisperForConditionalGeneration.from_pretrained(str(checkpoint), attn_implementation="eager").eval()
    model.config.return_dict = False
    model.config.tie_word_embeddings = False
    model.config.mask_neg = -100.0
    monkey_patch_model(model.model)

    class Encoder(torch.nn.Module):
        def __init__(self):
            super().__init__()
            self.encoder = model.get_encoder()

        def forward(self, input_features):
            return self.encoder(input_features)[0]

    class Decoder(torch.nn.Module):
        def __init__(self):
            super().__init__()
            self.decoder = model.get_decoder()

        def forward(self, *args):
            caches = args[2:-1]
            self_cache = tuple((caches[i], caches[i + 1]) for i in range(0, 24, 2))
            cross_cache = tuple((caches[i], caches[i + 1]) for i in range(24, 48, 2))
            logits, caches = self.decoder(input_ids=args[0], attention_mask=args[1],
                past_key_values=self_cache, cross_attn_past_key_value=cross_cache, position_ids=args[-1].to(torch.int64))
            return (logits, *(item for pair in caches for item in pair))

    encoder_names = [f"{p}_cache_cross_{i}" for i in range(12) for p in ("k", "v")]
    self_names = [f"{p}_cache_self_{i}_in" for i in range(12) for p in ("k", "v")]
    input_names = ["input_ids", "attention_mask", *self_names, *encoder_names, "position_ids"]
    output_names = ["logits", *(n.replace("_in", "_out") for n in self_names)]
    encoder_input = (torch.zeros(1, 80, 3000),)
    self_cache = [t for _ in range(12) for t in (torch.zeros(12, 1, 64, 199), torch.zeros(12, 1, 199, 64))]
    cross_cache = [t for _ in range(12) for t in (torch.zeros(12, 1, 64, 1500), torch.zeros(12, 1, 1500, 64))]
    decoder_input = (torch.tensor([[50258]], dtype=torch.int32), torch.full((1, 1, 1, 200), -100.0),
                     *self_cache, *cross_cache, torch.zeros(1, dtype=torch.int32))
    for name, module, sample, inputs, outputs in (
        ("encoder", Encoder(), encoder_input, ["input_features"], encoder_names),
        ("decoder", Decoder(), decoder_input, input_names, output_names),
    ):
        onnx = WORK / f"{name}.onnx"
        if not onnx.exists():
            print(f"Exporting {name} ONNX", flush=True)
            temporary_onnx = onnx.with_name(name + ".partial.onnx")
            with torch.no_grad():
                torch.onnx.export(module.eval(), sample, str(temporary_onnx), input_names=inputs,
                                  output_names=outputs, opset_version=17, dynamo=False)
            temporary_onnx.replace(onnx)
        output = ROOT / f"android/app/src/main/assets/whisper-qnn-generic/{name}.dlc"
        output.parent.mkdir(parents=True, exist_ok=True)
        if not output.exists():
            env = os.environ.copy()
            env["PYTHONUTF8"] = "1"
            env["PYTHONPATH"] = os.pathsep.join((str(WORK / "deps"), str(QAIRT / "lib/python")))
            print(f"Converting {name} to portable DLC", flush=True)
            temporary_dlc = output.with_name(name + ".partial.dlc")
            subprocess.run([sys.executable, str(QAIRT / "bin/x86_64-windows-msvc/qairt-converter"),
                            "--input_network", str(onnx), "--output_path", str(temporary_dlc),
                            "--float_bitwidth", "16"], env=env, check=True)
            temporary_dlc.replace(output)
    folder = ROOT / "android/app/src/main/assets/whisper-qnn-generic"
    files = [{"name": n, "bytes": (folder / n).stat().st_size, "sha256": digest(folder / n)}
             for n in ("encoder.dlc", "decoder.dlc")]
    revision = hashlib.sha256("".join(f["sha256"] for f in files).encode()).hexdigest()
    manifest = {"model": "openai/whisper-small", "checkpoint_revision": CHECKPOINT_REVISION,
                "reference_revision": REFERENCE_REVISION, "qairt": "2.50.0.260828", "soc": "generic",
                "revision": revision, "files": files}
    (folder / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("Portable Whisper DLCs prepared. They will compile for the phone's HTP on first use.", flush=True)


if __name__ == "__main__":
    main()
