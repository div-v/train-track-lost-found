package com.example.demo.service;

import com.google.firebase.database.DataSnapshot;
import com.google.firebase.database.DatabaseReference;
import com.google.firebase.database.FirebaseDatabase;
import com.google.firebase.messaging.AndroidConfig;
import com.google.firebase.messaging.AndroidNotification;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.MulticastMessage;
import com.google.firebase.messaging.Notification;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

/**
 * Sends chat push notifications to the recipient based on users/{uid}/fcmToken (single)
 * or users/{uid}/fcmTokens map in Realtime Database.
 * Reuses Admin SDK already configured in FirebaseConfig.
 */
@Service
public class ChatNotificationService {

    private final FirebaseMessaging fcm;
    private final DatabaseReference usersRef;

    public ChatNotificationService(FirebaseMessaging firebaseMessaging, FirebaseDatabase firebaseDatabase) {
        this.fcm = firebaseMessaging;
        this.usersRef = firebaseDatabase.getReference("users");
    }

    private Set<String> getAllTokensBlocking(String uid) {
        try {
            CompletableFuture<Set<String>> fut = new CompletableFuture<>();
            usersRef.child(uid).addListenerForSingleValueEvent(new com.google.firebase.database.ValueEventListener() {
                @Override
                public void onDataChange(DataSnapshot snap) {
                    Set<String> tokens = new HashSet<>();
                    // Legacy path: users/{uid}/fcmToken
                    if (snap.child("fcmToken").exists()) {
                        Object v = snap.child("fcmToken").getValue();
                        if (v != null) tokens.add(String.valueOf(v));
                    }
                    // Preferred path: users/{uid}/fcmTokens (map true)
                    if (snap.child("fcmTokens").exists()) {
                        for (DataSnapshot child : snap.child("fcmTokens").getChildren()) {
                            tokens.add(child.getKey());
                        }
                    }
                    fut.complete(tokens);
                }

                @Override
                public void onCancelled(com.google.firebase.database.DatabaseError error) {
                    fut.completeExceptionally(new RuntimeException(error.getMessage()));
                }
            });
            return fut.get(5, TimeUnit.SECONDS);
        } catch (Exception e) {
            e.printStackTrace();
            return Collections.emptySet();
        }
    }

    public void sendChat(String toUid, String title, String body, String cid, String itemId) {
        Set<String> tokens = getAllTokensBlocking(toUid);
        if (tokens.isEmpty()) {
            System.out.println("No tokens for user " + toUid);
            return;
        }

        MulticastMessage msg = MulticastMessage.builder()
                .addAllTokens(tokens)
                .setNotification(Notification.builder()
                        .setTitle(title)
                        .setBody(body)
                        .build())
                .putData("type", "chat")
                .putData("cid", cid == null ? "" : cid)
                .putData("itemId", itemId == null ? "" : itemId)
                .setAndroidConfig(AndroidConfig.builder()
                        .setNotification(AndroidNotification.builder()
                                .setChannelId("chat_messages")
                                .build())
                        .build())
                .build();

        try {
            var resp = fcm.sendEachForMulticast(msg);
            System.out.println("Chat FCM sent: success=" + resp.getSuccessCount() + " failure=" + resp.getFailureCount());
            // Optional: prune invalid tokens by inspecting resp.getResponses()
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}

