package com.quotapp.api.exception;

public class UnrecognizedUnitException extends RuntimeException {
    private final String unit;

    public UnrecognizedUnitException(String unit) {
        super("Unrecognized contractor unit: '" + unit + "'. Allowed units: sq ft, rft, brass, nos, lumpsum, bags, point.");
        this.unit = unit;
    }

    public String getUnit() {
        return unit;
    }
}
