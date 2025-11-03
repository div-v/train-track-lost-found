package com.example.demo.job;

import com.example.demo.service.ChatNotificationService;
import com.google.api.core.ApiFutureCallback;
import com.google.api.core.ApiFutures;
import com.google.cloud.firestore.*;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import com.google.cloud.Timestamp;
import com.google.cloud.firestore.Transaction;
import com.google.cloud.firestore.DocumentSnapshot;
// Firestore Timestamp


import java.util.*;
import java.util.concurrent.Executor;
import java.util.concurrent.Executors;

@Component
public class ChatMessageListener {

    private static final Logger log = LoggerFactory.getLogger(ChatMessageListener.class);

    private final Firestore db;
    private final ChatNotificationService chatNotifier;
    private ListenerRegistration registration;
    private final Executor exec = Executors.newSingleThreadExecutor();
    private volatile boolean initialLoaded = false;

    public ChatMessageListener(Firestore db, ChatNotificationService chatNotifier) {
        this.db = db;
        this.chatNotifier = chatNotifier;
    }

    @PostConstruct
    public void start() {
        try {
            // Listen to newest messages; ensure index on createdAt if needed
            Query q = db.collectionGroup("messages")
                    .orderBy("createdAt", Query.Direction.DESCENDING)
                    .limit(50);

            registration = q.addSnapshotListener(exec, (snap, err) -> {
                if (err != null) {
                    log.error("Chat listener error", err);
                    return;
                }
                if (snap == null) return;

                // Skip the initial bootstrap batch to avoid re-sending recent messages
                if (!initialLoaded) {
                    initialLoaded = true;
                    return;
                }

                List<DocumentChange> changes = snap.getDocumentChanges();
                if (changes == null || changes.isEmpty()) return;

                for (DocumentChange dc : changes) {
                    if (dc.getType() != DocumentChange.Type.ADDED) continue;
                    handleAdded(dc.getDocument());
                }
            });

            log.info("ChatMessageListener started.");
        } catch (Exception e) {
            log.error("Failed to start ChatMessageListener", e);
        }
    }

    private void handleAdded(DocumentSnapshot msgDoc) {
        Map<String, Object> m = msgDoc.getData();
        if (m == null) return;

        String senderUid = str(m.get("senderUid"));
        String text = str(m.get("text"));
        String imageUrl = str(m.get("imageUrl"));
        boolean hasImage = imageUrl != null && !imageUrl.isBlank();
        String body = (text != null && !text.isBlank()) ? text : (hasImage ? "Photo" : "New message");

        DocumentReference convRef = msgDoc.getReference().getParent().getParent();
        if (convRef == null) return;

        ApiFutures.addCallback(
                convRef.get(),
                new ApiFutureCallback<DocumentSnapshot>() {
                    @Override
                    public void onSuccess(DocumentSnapshot conv) {
                        try {
                            if (!conv.exists()) return;
                            Map<String, Object> cd = conv.getData();
                            if (cd == null) return;

                            List<String> participants = toStringList(cd.get("participants"));
                            if (participants.size() != 2) return;
                            String itemId = str(cd.get("itemId"));
                            String cid = conv.getId();

                            String toUid = participants.get(0).equals(senderUid) ? participants.get(1) : participants.get(0);
                            if (toUid == null || toUid.isBlank() || toUid.equals(senderUid)) return;

                            processNotificationIfEligible(msgDoc, conv, toUid, cid, itemId, body);
                        } catch (Exception e) {
                            log.error("Chat notification processing failed", e);
                        }
                    }

                    @Override
                    public void onFailure(Throwable t) {
                        log.error("Failed to load conversation", t);
                    }
                },
                exec
        );
    }

    /**
     * Uses a Firestore transaction to create an idempotency marker deliveries/{messageId_recipientUid}.
     * Returns true from the transaction when a new marker is written (i.e., should send).
     * Also performs an optional "newest-only" check against conversation.lastMessageAt if present.
     */
    private void processNotificationIfEligible(
            DocumentSnapshot msgDoc,
            DocumentSnapshot conv,
            String toUid,
            String cid,
            String itemId,
            String body
    ) {
        try {
            String deliveryId = msgDoc.getId() + "_" + toUid;
            DocumentReference deliveryRef = db.collection("deliveries").document(deliveryId);

            Timestamp msgAt = msgDoc.getTimestamp("createdAt");
            Timestamp lastAt = conv.getTimestamp("lastMessageAt");

            // Run transaction: if marker absent and (optionally) message is newest, create marker and return true; else false.
            Boolean shouldSend = db.runTransaction((Transaction t) -> {
                DocumentSnapshot d = t.get(deliveryRef).get(); // correct: returns DocumentSnapshot
                if (d.exists()) {
                    return false;
                }
                if (lastAt != null && msgAt != null && msgAt.compareTo(lastAt) < 0) {
                    return false;
                }
                Map<String, Object> delivery = new HashMap<>();
                delivery.put("createdAt", FieldValue.serverTimestamp());
                delivery.put("conversationId", cid);
                delivery.put("recipientUid", toUid);
                delivery.put("messageId", msgDoc.getId());
                t.set(deliveryRef, delivery);
                return true;
            }).get();

            if (Boolean.TRUE.equals(shouldSend)) {
                String title = "New message";
                chatNotifier.sendChat(toUid, title, (body == null || body.isBlank()) ? "New message" : body, cid, itemId);
            }
        } catch (Exception e) {
            log.error("processNotificationIfEligible failed", e);
        }
    }

    private static String str(Object o) {
        return o == null ? "" : String.valueOf(o);
    }

    @SuppressWarnings("unchecked")
    private static List<String> toStringList(Object o) {
        if (o instanceof List<?> l) {
            List<String> out = new ArrayList<>();
            for (Object x : l) out.add(str(x));
            return out;
        }
        return Collections.emptyList();
    }
}
