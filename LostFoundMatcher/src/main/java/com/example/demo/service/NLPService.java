package com.example.demo.service;

import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import org.springframework.http.ResponseEntity;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

import java.util.HashMap;
import java.util.Map;

@Service
public class NLPService {

    private final RestTemplate restTemplate = new RestTemplate();
    private final String NLP_URL = "http://127.0.0.1:5000/similarity";

    public double getSimilarity(String desc1, String desc2) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);

        Map<String, String> request = new HashMap<>();
        request.put("desc1", desc1);
        request.put("desc2", desc2);

        HttpEntity<Map<String, String>> entity = new HttpEntity<>(request, headers);

        ResponseEntity<Map> response = restTemplate.postForEntity(NLP_URL, entity, Map.class);
        return ((Number) response.getBody().get("similarity")).doubleValue();

    }
}
