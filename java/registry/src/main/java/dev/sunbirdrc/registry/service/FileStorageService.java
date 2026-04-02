package dev.sunbirdrc.registry.service;

import io.minio.*;
import io.minio.errors.*;
import io.minio.http.Method;
import io.minio.messages.DeleteError;
import io.minio.messages.DeleteObject;
import dev.sunbirdrc.registry.model.dto.DocumentsResponse;
import org.apache.poi.util.IOUtils;
import org.jetbrains.annotations.NotNull;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Paths;
import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

@Service
public class FileStorageService {
    private static final Logger logger = LoggerFactory.getLogger(FileStorageService.class);
    private final MinioClient minioClient;
    private final String bucketName;

    private static final int MAX_OBJECT_SIZE = 10485760; // 10 MB
    private static final int PRESIGNED_URL_EXPIRY_HOURS = 2;
    private static final String VERSION_DELIMITER = "/v1/";
    private static final Set<String> ALLOWED_CONTENT_TYPES = new HashSet<>(Arrays.asList(
            "application/pdf", "image/jpeg", "image/png", "image/gif",
            "application/msword", "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "text/plain", "application/json"
    ));

    public FileStorageService(MinioClient minioClient, @Value("${filestorage.bucketname}") String bucketName) {
        this.bucketName = bucketName;
        this.minioClient = minioClient;
    }

    public void save(InputStream inputStream, String objectName) throws Exception {
        ensureBucketExists();
        logger.info("Saving the file in the location {}", objectName);
        minioClient.putObject(PutObjectArgs.builder()
                .bucket(bucketName)
                .object(objectName)
                .stream(inputStream, -1, MAX_OBJECT_SIZE)
                .build());
        logger.info("File has successfully saved");
    }

    private void ensureBucketExists() throws Exception {
        if (!isBucketExists()) {
            logger.info("Bucket {} doesn't exist, creating new bucket", bucketName);
            createNewBucket();
        }
    }

    private void createNewBucket() throws ErrorResponseException, InsufficientDataException, InternalException, InvalidKeyException, InvalidResponseException, IOException, NoSuchAlgorithmException, ServerException, XmlParserException {
        minioClient.makeBucket(MakeBucketArgs
                .builder()
                .bucket(bucketName)
                .build());
    }

    private boolean isBucketExists() throws ErrorResponseException, InsufficientDataException, InternalException, InvalidKeyException, InvalidResponseException, IOException, NoSuchAlgorithmException, ServerException, XmlParserException {
        return minioClient.bucketExists(BucketExistsArgs
                .builder()
                .bucket(bucketName)
                .build());
    }

    public DocumentsResponse saveAndFetchFileNames(MultipartFile[] files, String requestedURI) {
        String objectPath = getDirectoryPath(requestedURI);

        DocumentsResponse documentsResponse = new DocumentsResponse();
        for (MultipartFile file : files) {
            String originalFilename = file.getOriginalFilename();

            if (!isValidFileType(file)) {
                documentsResponse.addError(originalFilename + " (unsupported file type)");
                logger.warn("Rejected file upload with unsupported content type: {}", file.getContentType());
                continue;
            }

            String fileName = getFileName(sanitizeFilename(originalFilename));
            try {
                String objectName = objectPath + "/" + fileName;
                save(file.getInputStream(), objectName);
                documentsResponse.addDocumentLocation(objectName);
            } catch (Exception e) {
                documentsResponse.addError(originalFilename);
                logger.error("Error has occurred while trying to save the file {}", fileName, e);
            }
        }
        return documentsResponse;
    }

    private boolean isValidFileType(MultipartFile file) {
        String contentType = file.getContentType();
        return contentType != null && ALLOWED_CONTENT_TYPES.contains(contentType.toLowerCase());
    }

    @NotNull
    private String sanitizeFilename(String filename) {
        if (filename == null || filename.isEmpty()) {
            return "unnamed";
        }
        // Remove path separators and parent directory references
        String sanitized = Paths.get(filename).getFileName().toString();
        // Remove any remaining dangerous characters
        sanitized = sanitized.replaceAll("[^a-zA-Z0-9._-]", "_");
        return sanitized.isEmpty() ? "unnamed" : sanitized;
    }

    String getDirectoryPath(String requestedURI) {
        if (requestedURI == null || !requestedURI.contains(VERSION_DELIMITER)) {
            throw new IllegalArgumentException("Invalid request URI format");
        }
        String[] split = requestedURI.split(VERSION_DELIMITER, 2);
        if (split.length < 2 || split[1].isEmpty()) {
            throw new IllegalArgumentException("Invalid request URI format");
        }
        String path = split[1];
        // Prevent path traversal
        String normalized = Paths.get(path).normalize().toString();
        if (normalized.startsWith("..") || normalized.contains("/../") || normalized.startsWith("/")) {
            throw new IllegalArgumentException("Invalid path: path traversal detected");
        }
        return normalized;
    }

    @NotNull
    private String getFileName(String file) {
        String uuid = UUID.randomUUID().toString();
        return uuid + "-" + file;
    }

    public DocumentsResponse deleteFiles(List<String> files) {
        DocumentsResponse documentsResponse = new DocumentsResponse();
        List<DeleteObject> deleteObjects = files.stream().map(DeleteObject::new).collect(Collectors.toList());
        Iterable<Result<DeleteError>> results = minioClient.removeObjects(RemoveObjectsArgs.builder()
                .bucket(bucketName)
                .objects(deleteObjects)
                .build());
        for (Result<DeleteError> result : results) {
            try {
                documentsResponse.addError(result.get().bucketName());
            } catch (Exception e) {
                logger.error("Error has occurred while fetching the delete error result", e);
            }
        }
        return documentsResponse;
    }

    public String getSignedUrl(String objectName) throws ServerException, InsufficientDataException, ErrorResponseException, IOException, NoSuchAlgorithmException, InvalidKeyException, InvalidResponseException, XmlParserException, InternalException {
        return minioClient.getPresignedObjectUrl(
                GetPresignedObjectUrlArgs.builder()
                        .method(Method.GET)
                        .bucket(bucketName)
                        .object(objectName)
                        .expiry(PRESIGNED_URL_EXPIRY_HOURS, TimeUnit.HOURS)
                        .build());
    }

    public byte[] getDocument(String requestedURI) {
        String objectName = getDirectoryPath(requestedURI);
        try (InputStream inputStream = minioClient.getObject(
                GetObjectArgs.builder()
                        .bucket(bucketName)
                        .object(objectName)
                        .build())) {
            return IOUtils.toByteArray(inputStream);
        } catch (Exception e) {
            logger.error("Error has occurred while fetching the document {}", objectName, e);
            return new byte[0];
        }
    }

    public ResponseEntity<Void> deleteDocument(String requestedURI) {
        String objectName = getDirectoryPath(requestedURI);
        try {
            minioClient.removeObject(RemoveObjectArgs.builder().bucket(bucketName).object(objectName).build());
        } catch (Exception e) {
            logger.error("Error has occurred while deleting the document {}", objectName, e);
            return new ResponseEntity<>(HttpStatus.BAD_REQUEST);
        }
        return new ResponseEntity<>(HttpStatus.OK);
    }
}
