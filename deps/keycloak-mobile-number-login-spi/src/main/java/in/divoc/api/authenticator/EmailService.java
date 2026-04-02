package in.divoc.api.authenticator;

import org.jboss.logging.Logger;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

public class EmailService {
    private static final Logger logger = Logger.getLogger(EmailService.class);
    private static final String SENDINBLUE_API_URL = "https://api.sendinblue.com/v3/smtp/email";

    void sendEmail(String email, String otp) {
        String apiKey = System.getenv("SENDINBLUE_API_KEY");
        if (apiKey == null || apiKey.isEmpty()) {
            logger.error("SENDINBLUE_API_KEY environment variable is not set");
            return;
        }
        try {
            URL url = new URL(SENDINBLUE_API_URL);
            HttpURLConnection con = (HttpURLConnection) url.openConnection();
            con.setRequestMethod("POST");
            con.setRequestProperty("content-type", "application/json");
            con.setRequestProperty("accept", "application/json");
            con.setRequestProperty("api-key", apiKey);
            con.setRequestProperty("Host", "api.sendinblue.com");

            con.setDoOutput(true);
            String jsonInputString = "{  \n   \"sender\":{  \n      \"name\":\"NDEAR\",\n      \"email\":\"no-reply@ndear.xiv.in\"\n   },\n   \"to\":[  \n      {  \n         \"email\": \""  + email + "\",\n         \"name\":\""+email+"\"\n      }\n   ],\n   \"subject\":\"NDEAR - LOGIN OTP\",\n   \"htmlContent\":\"<html><head></head><body><p>Your One Time Password(OTP) is :</p><h1> " + otp + "</h1></p></body></html>\"\n}";
            try (OutputStream os = con.getOutputStream()) {
                byte[] input = jsonInputString.getBytes(StandardCharsets.UTF_8);
                os.write(input, 0, input.length);
            }
            try (BufferedReader br = new BufferedReader(
                    new InputStreamReader(con.getInputStream(), StandardCharsets.UTF_8))) {
                StringBuilder response = new StringBuilder();
                String responseLine;
                while ((responseLine = br.readLine()) != null) {
                    response.append(responseLine.trim());
                }
                logger.debug("Email API response received successfully");
            }
        } catch (IOException e) {
            logger.error("Failed to send email", e);
        }
    }
}