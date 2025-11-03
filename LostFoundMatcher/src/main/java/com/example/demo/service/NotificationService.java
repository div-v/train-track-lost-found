package com.example.demo.service;

import com.google.firebase.database.DataSnapshot;
import com.google.firebase.database.DatabaseError;
import com.google.firebase.database.DatabaseReference;
import com.google.firebase.database.FirebaseDatabase;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.Notification;
import org.springframework.stereotype.Service;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

@Service
public class NotificationService {

    private final FirebaseMessaging firebaseMessaging;
    private final DatabaseReference usersRef;

    public NotificationService(FirebaseMessaging firebaseMessaging, FirebaseDatabase firebaseDatabase) {
        this.firebaseMessaging = firebaseMessaging;
        this.usersRef = firebaseDatabase.getReference("users");
    }

    // Works across Admin SDK versions: use a single-value listener and a CompletableFuture
    private String getUserFcmTokenBlocking(String uid) {
        try { 
            CompletableFuture<String> future = new CompletableFuture<>();
            usersRef.child(uid).child("fcmToken")
                    .addListenerForSingleValueEvent(new com.google.firebase.database.ValueEventListener() {
                        @Override
                        public void onDataChange(DataSnapshot snapshot) {
                            if (snapshot.exists() && snapshot.getValue() != null) {
                                future.complete(String.valueOf(snapshot.getValue()));
                            } else {
                                future.complete(null);
                            }
                        }
                        @Override
                        public void onCancelled(DatabaseError error) {
                            future.completeExceptionally(
                                    new RuntimeException("RTDB read cancelled: " + error.getMessage()));
                        }
                    });

            // Wait up to 5 seconds to avoid hanging
            return future.get(10, TimeUnit.SECONDS);
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }

    public boolean sendToUser(String uid, String title, String body) {
        try {
            String token = getUserFcmTokenBlocking(uid);
            if (token == null || token.isBlank()) {
                System.out.println("No FCM token for user " + uid);
                return false;
            }

            Message msg = Message.builder()
                    .setToken(token)
                    .setNotification(Notification.builder()
                            .setTitle(title)
                            .setBody(body)
                            .build())
                    .putData("type", "match")
                    .build();

            String id = firebaseMessaging.send(msg);
            System.out.println("Sent FCM to " + uid + " msgId=" + id);
            return true;
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    public void notifyMatchPair(String userAUid, String userBUid, String titleA, String titleB) {
        sendToUser(userAUid, "Match found!", "A found item matches your lost post: " + titleA);
        sendToUser(userBUid, "Match found!", "A lost item matches your found post: " + titleB);
    }
}
