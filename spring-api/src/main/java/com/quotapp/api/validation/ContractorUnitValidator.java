package com.quotapp.api.validation;

import com.quotapp.api.dto.ContractorUnit;
import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;

public class ContractorUnitValidator implements ConstraintValidator<ValidContractorUnit, String> {

    @Override
    public boolean isValid(String value, ConstraintValidatorContext context) {
        if (value == null || value.isBlank()) {
            return false;
        }
        return ContractorUnit.isRecognized(value);
    }
}
