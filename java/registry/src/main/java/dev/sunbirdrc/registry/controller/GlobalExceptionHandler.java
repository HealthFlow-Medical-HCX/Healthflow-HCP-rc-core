package dev.sunbirdrc.registry.controller;

import dev.sunbirdrc.pojos.Response;
import dev.sunbirdrc.pojos.ResponseParams;
import dev.sunbirdrc.registry.exception.RecordNotFoundException;
import dev.sunbirdrc.registry.exception.UnAuthorizedException;
import dev.sunbirdrc.registry.middleware.MiddlewareHaltException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ExceptionHandler;

@ControllerAdvice
public class GlobalExceptionHandler {
    private static final Logger logger = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(UnAuthorizedException.class)
    public ResponseEntity<Object> handleUnauthorized(UnAuthorizedException ex) {
        logger.warn("Unauthorized access: {}", ex.getMessage());
        ResponseParams responseParams = new ResponseParams();
        responseParams.setStatus(Response.Status.UNSUCCESSFUL);
        responseParams.setErrmsg("Unauthorized");
        Response response = new Response(Response.API_ID.UPDATE, "ERROR", responseParams);
        return new ResponseEntity<>(response, HttpStatus.UNAUTHORIZED);
    }

    @ExceptionHandler(RecordNotFoundException.class)
    public ResponseEntity<Object> handleNotFound(RecordNotFoundException ex) {
        logger.warn("Record not found: {}", ex.getMessage());
        ResponseParams responseParams = new ResponseParams();
        responseParams.setStatus(Response.Status.UNSUCCESSFUL);
        responseParams.setErrmsg("Record not found");
        Response response = new Response(Response.API_ID.READ, "ERROR", responseParams);
        return new ResponseEntity<>(response, HttpStatus.NOT_FOUND);
    }

    @ExceptionHandler(MiddlewareHaltException.class)
    public ResponseEntity<Object> handleValidation(MiddlewareHaltException ex) {
        logger.warn("Validation error: {}", ex.getMessage());
        ResponseParams responseParams = new ResponseParams();
        responseParams.setStatus(Response.Status.UNSUCCESSFUL);
        responseParams.setErrmsg("Validation failed");
        Response response = new Response(Response.API_ID.CREATE, "ERROR", responseParams);
        return new ResponseEntity<>(response, HttpStatus.BAD_REQUEST);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<Object> handleBadRequest(IllegalArgumentException ex) {
        logger.warn("Bad request: {}", ex.getMessage());
        ResponseParams responseParams = new ResponseParams();
        responseParams.setStatus(Response.Status.UNSUCCESSFUL);
        responseParams.setErrmsg("Invalid request");
        Response response = new Response(Response.API_ID.UPDATE, "ERROR", responseParams);
        return new ResponseEntity<>(response, HttpStatus.BAD_REQUEST);
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<Object> handleGenericException(Exception ex) {
        logger.error("Unhandled exception", ex);
        ResponseParams responseParams = new ResponseParams();
        responseParams.setStatus(Response.Status.UNSUCCESSFUL);
        responseParams.setErrmsg("An internal error occurred");
        Response response = new Response(Response.API_ID.UPDATE, "ERROR", responseParams);
        return new ResponseEntity<>(response, HttpStatus.INTERNAL_SERVER_ERROR);
    }
}
