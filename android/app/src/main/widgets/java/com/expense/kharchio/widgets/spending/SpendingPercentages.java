package com.expense.kharchio.widgets.spending;

import java.util.Arrays;

/** Largest remainder rounding: displayed whole percentages sum to exactly 100. */
final class SpendingPercentages {
    static int[] allocate(long[] amounts) {
        long total = 0;
        for (long value : amounts) {
            if (value < 0) throw new IllegalArgumentException("Negative spending");
            total = Math.addExact(total, value);
        }
        int[] result = new int[amounts.length];
        if (total == 0) return result;
        double[] fractions = new double[amounts.length];
        Integer[] order = new Integer[amounts.length];
        int assigned = 0;
        for (int i = 0; i < amounts.length; i++) {
            double exact = amounts[i] * 100.0 / total;
            result[i] = (int) Math.floor(exact);
            fractions[i] = exact - result[i];
            assigned += result[i];
            order[i] = i;
        }
        Arrays.sort(order, (a,b) -> {
            int difference = Double.compare(fractions[b], fractions[a]);
            return difference == 0 ? Integer.compare(a,b) : difference;
        });
        for (int i = 0; i < 100-assigned; i++) result[order[i]]++;
        return result;
    }
}
