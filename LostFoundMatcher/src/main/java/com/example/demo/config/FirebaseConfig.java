package com.example.demo.config;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.cloud.FirestoreClient;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.cloud.firestore.Firestore;
import com.google.firebase.database.FirebaseDatabase;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

@Configuration
public class FirebaseConfig {

  @Value("${app.firebase.project-id}")
  private String projectId;

  @Value("${app.firebase.service-account-path:}")
  private String serviceAccountPath;

  // ADD your RTDB URL here (match your Firebase project)
  @Value("${app.firebase.database-url}")
  private String databaseUrl;

  @Bean
  public FirebaseApp firebaseApp() throws Exception {
    FirebaseOptions.Builder builder = FirebaseOptions.builder();
    GoogleCredentials credentials;
    String credsJson = System.getenv("FIREBASE_SERVICE_ACCOUNT_JSON");
    if (credsJson != null && !credsJson.isBlank()) {
      try (InputStream is = new ByteArrayInputStream(credsJson.getBytes(StandardCharsets.UTF_8))) {
        credentials = GoogleCredentials.fromStream(is);
      }
    } else if (serviceAccountPath != null && !serviceAccountPath.isBlank()) {
      try (InputStream is = FirebaseConfig.class.getResourceAsStream(serviceAccountPath.replace("classpath:", "/"))) {
        if (is == null) throw new IllegalStateException("Service account file not found: " + serviceAccountPath);
        credentials = GoogleCredentials.fromStream(is);
      }
    } else {
      credentials = GoogleCredentials.getApplicationDefault();
    }
    builder.setCredentials(credentials);
    if (projectId != null && !projectId.isBlank()) {
      builder.setProjectId(projectId);
    }
    // IMPORTANT: set database URL so Admin SDK can access RTDB
    if (databaseUrl != null && !databaseUrl.isBlank()) {
      builder.setDatabaseUrl(databaseUrl);
    }
    return FirebaseApp.initializeApp(builder.build());
  }

  @Bean
  public Firestore firestore(FirebaseApp app) {
    return FirestoreClient.getFirestore(app);
  }

  @Bean
  public FirebaseMessaging firebaseMessaging(FirebaseApp app) {
    return FirebaseMessaging.getInstance(app);
  }

  @Bean
  public FirebaseDatabase firebaseDatabase(FirebaseApp app) {
    // Using the app that already has databaseUrl configured
    FirebaseDatabase db = FirebaseDatabase.getInstance(app);
    // Server-side: keep persistence off
    db.setPersistenceEnabled(false);
    return db;
  }
}
