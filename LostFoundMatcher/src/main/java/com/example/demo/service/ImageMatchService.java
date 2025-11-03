package com.example.demo.service;

import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import org.springframework.http.*;

import java.util.HashMap;
import java.util.Map;

@Service
public class ImageMatchService {

    private final RestTemplate restTemplate = new RestTemplate();
    // Make sure this matches your Flask image service
    private final String IMAGE_URL = "http://127.0.0.1:5001/image_similarity";

    public double getSimilarity(String imgUrl1, String imgUrl2) {
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);

            Map<String, String> request = new HashMap<>();
            request.put("img1", imgUrl1);
            request.put("img2", imgUrl2);

            HttpEntity<Map<String, String>> entity = new HttpEntity<>(request, headers);

            ResponseEntity<Map> response = restTemplate.postForEntity(IMAGE_URL, entity, Map.class);

            if (response.getBody().containsKey("similarity")) {
                return ((Number) response.getBody().get("similarity")).doubleValue();
            } else {
                return 0.0; // fallback if response doesn't contain similarity
            }
        } catch (Exception e) {
            e.printStackTrace();
            return 0.0;
        }
    }
}
