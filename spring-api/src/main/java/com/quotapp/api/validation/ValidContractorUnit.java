package com.quotapp.api.validation;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

@Target({ElementType.FIELD, ElementType.PARAMETER, ElementType.TYPE_USE})
@Retention(RetentionPolicy.RUNTIME)
@Constraint(validatedBy = ContractorUnitValidator.class)
@Documented
public @interface ValidContractorUnit {
    String message() default "Unrecognized unit. Allowed units: sq ft, rft, brass, nos, lumpsum, bags, point.";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}
