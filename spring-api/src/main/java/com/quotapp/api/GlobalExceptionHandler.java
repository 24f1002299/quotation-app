package com.quotapp.api;

import com.quotapp.api.dto.ErrorResponse;
import com.quotapp.api.dto.ErrorResponse.FieldErrorDetail;
import com.quotapp.api.exception.OwnershipViolationException;
import com.quotapp.api.exception.UnrecognizedUnitException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.HttpMediaTypeNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.multipart.MaxUploadSizeExceededException;

import java.util.List;

/**
 * Central exception handler producing consistent, safe, structured error responses.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleValidationErrors(MethodArgumentNotValidException ex) {
        List<FieldErrorDetail> details = ex.getBindingResult().getFieldErrors().stream()
            .map(err -> new FieldErrorDetail(
                err.getField(),
                err.getRejectedValue(),
                err.getDefaultMessage()
            ))
            .toList();

        log.warn("Request validation failed with {} field error(s)", details.size());
        ErrorResponse response = new ErrorResponse(
            "VALIDATION_FAILED",
            "Validation failed for one or more request fields",
            details
        );
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(response);
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ErrorResponse> handleMessageNotReadable(HttpMessageNotReadableException ex) {
        log.warn("Malformed JSON payload received: {}", ex.getMessage());
        ErrorResponse response = new ErrorResponse(
            "MALFORMED_JSON",
            "Malformed JSON or unreadable request body"
        );
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(response);
    }

    @ExceptionHandler(UnrecognizedUnitException.class)
    public ResponseEntity<ErrorResponse> handleUnrecognizedUnit(UnrecognizedUnitException ex) {
        log.warn("Unrecognized unit: {}", ex.getUnit());
        ErrorResponse response = new ErrorResponse(
            "UNRECOGNIZED_UNIT",
            ex.getMessage()
        );
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(response);
    }

    @ExceptionHandler(OwnershipViolationException.class)
    public ResponseEntity<ErrorResponse> handleOwnershipViolation(OwnershipViolationException ex) {
        log.warn("Ownership violation: {}", ex.getMessage());
        ErrorResponse response = new ErrorResponse(
            "OWNERSHIP_VIOLATION",
            ex.getMessage()
        );
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(response);
    }

    @ExceptionHandler(MaxUploadSizeExceededException.class)
    public ResponseEntity<ErrorResponse> handleMaxSizeExceeded(MaxUploadSizeExceededException ex) {
        log.warn("Upload size limit exceeded: {}", ex.getMessage());
        ErrorResponse response = new ErrorResponse(
            "FILE_TOO_LARGE",
            "Audio upload exceeds maximum allowed size of 10MB"
        );
        return ResponseEntity.status(HttpStatus.PAYLOAD_TOO_LARGE).body(response);
    }

    @ExceptionHandler(HttpMediaTypeNotSupportedException.class)
    public ResponseEntity<ErrorResponse> handleUnsupportedMediaType(HttpMediaTypeNotSupportedException ex) {
        log.warn("Unsupported media type: {}", ex.getContentType());
        ErrorResponse response = new ErrorResponse(
            "UNSUPPORTED_MEDIA_TYPE",
            "Content-Type not supported: " + ex.getContentType()
        );
        return ResponseEntity.status(HttpStatus.UNSUPPORTED_MEDIA_TYPE).body(response);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ErrorResponse> handleIllegalArgument(IllegalArgumentException ex) {
        log.warn("Illegal argument: {}", ex.getMessage());
        ErrorResponse response = new ErrorResponse(
            "INVALID_REQUEST",
            ex.getMessage()
        );
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(response);
    }

    @ExceptionHandler(org.springframework.web.servlet.resource.NoResourceFoundException.class)
    public ResponseEntity<ErrorResponse> handleNoResourceFound(org.springframework.web.servlet.resource.NoResourceFoundException ex) {
        log.warn("Resource not found: {}", ex.getResourcePath());
        ErrorResponse response = new ErrorResponse(
            "NOT_FOUND",
            "Resource not found: " + ex.getResourcePath()
        );
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(response);
    }

    @ExceptionHandler(org.springframework.web.HttpRequestMethodNotSupportedException.class)
    public ResponseEntity<ErrorResponse> handleMethodNotSupported(org.springframework.web.HttpRequestMethodNotSupportedException ex) {
        log.warn("Method not supported: {}", ex.getMethod());
        ErrorResponse response = new ErrorResponse(
            "METHOD_NOT_ALLOWED",
            "HTTP method not allowed: " + ex.getMethod()
        );
        return ResponseEntity.status(HttpStatus.METHOD_NOT_ALLOWED).body(response);
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleGenericException(Exception ex) {
        log.error("Unhandled error: ", ex);
        ErrorResponse response = new ErrorResponse(
            "INTERNAL_ERROR",
            "An unexpected error occurred while processing the request"
        );
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(response);
    }
}
