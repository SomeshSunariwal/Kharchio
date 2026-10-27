"""Provision the pinned official Whisper Small SM8550 contexts and QAIRT runtime."""
import argparse
import hashlib
import json
import shutil
import urllib.request
import zipfile
from pathlib import Path

NATIVE = Path(__file__).resolve().parents[2]
ROOT = NATIVE.parent


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def archive(path, url, sha256):
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        partial = path.with_suffix(".partial")
        print(f"Downloading {url}", flush=True)
        with urllib.request.urlopen(url) as source, partial.open("wb") as output:
            shutil.copyfileobj(source, output)
        if digest(partial) != sha256:
            raise ValueError(f"Download checksum mismatch: {partial}")
        partial.replace(path)
    if digest(path) != sha256:
        raise ValueError(f"Archive checksum mismatch: {path}")
    return zipfile.ZipFile(path)


def extract(source, member, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_suffix(target.suffix + ".partial")
    with source.open(member) as data, partial.open("wb") as output:
        shutil.copyfileobj(data, output)
    partial.replace(target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk-zip", type=Path, default=ROOT / ".tmp/model-downloads/qairt.zip")
    parser.add_argument("--model-zip", type=Path, default=ROOT / ".tmp/model-downloads/whisper-small-sm8550.zip")
    parser.add_argument("--include-converter", action="store_true")
    args = parser.parse_args()
    lock = json.loads((NATIVE / "config/whisper_qnn.lock.json").read_text())
    prefix = f"qairt/{lock['qairt']}/"
    destination = NATIVE / "prebuilt/qairt"
    libraries = ROOT / "android/app/src/main/jniLibs/arm64-v8a"
    # HTP/System only. No QNN CPU/GPU provider is bundled or loaded.
    architectures = (68, 69, 73, 75, 79, 81)
    android_libs = ["libQnnHtp.so", "libQnnSystem.so", "libQnnHtpPrepare.so"]
    android_libs += [f"libQnnHtpV{v}Stub.so" for v in architectures]
    with archive(args.sdk_zip, lock["sdk_url"], lock["sdk_sha256"]) as sdk:
        for name in sdk.namelist():
            if name.startswith(prefix + "include/QNN/") and not name.endswith("/"):
                extract(sdk, name, destination / name)
            if args.include_converter and not name.endswith("/") and (
                name.startswith(prefix + "lib/python/") or name == prefix + "bin/x86_64-windows-msvc/qairt-converter"):
                extract(sdk, name, destination / name)
        for name in android_libs:
            extract(sdk, prefix + "lib/aarch64-android/" + name, libraries / name)
        for version in architectures:
            for name in (f"libQnnHtpV{version}Skel.so", f"libQnnHtpV{version}.so"):
                extract(sdk, prefix + f"lib/hexagon-v{version}/unsigned/" + name, libraries / name)
        extract(sdk, prefix + "LICENSE.pdf", destination / "LICENSE.pdf")
    assets = ROOT / "models/whisper/android/whisper-qnn-sm8550"
    files = []
    with archive(args.model_zip, lock["model_url"], lock["model_sha256"]) as model:
        folder = "whisper_small-qnn_context_binary-float-qualcomm_qcs8550_proxy/"
        metadata = json.loads(model.read(folder + "metadata.json"))
        if metadata["tool_versions"]["qairt"] != lock["qairt_build"]:
            raise ValueError("QNN context / runtime version mismatch")
        for name in ("encoder.bin", "decoder.bin"):
            target = assets / f"whisper-s23-{name}"
            extract(model, folder + name, target)
            files.append({"name": target.name, "bytes": target.stat().st_size, "sha256": digest(target)})
    manifest = {"model": lock["model"], "release": lock["release"], "soc": lock["soc"],
                "qairt": lock["qairt_build"], "files": files}
    (assets / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("Whisper Small QNN/QAIRT for Snapdragon 8 Gen 2 is installed and verified.")


if __name__ == "__main__":
    main()
