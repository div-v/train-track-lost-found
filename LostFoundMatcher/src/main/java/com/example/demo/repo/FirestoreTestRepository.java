package com.example.demo.repo;

import com.google.cloud.Timestamp;
import com.google.cloud.firestore.*;
import org.springframework.stereotype.Repository;

import java.util.*;

@Repository
public class FirestoreTestRepository {

    private final Firestore db;

    public FirestoreTestRepository(Firestore db) {
        this.db = db;
    }

    public void printLatestItems(int limit) throws Exception {
        Query q = db.collection("items")
                .orderBy("timestamp", Query.Direction.DESCENDING)
                .limit(limit);
        List<QueryDocumentSnapshot> docs = q.get().get().getDocuments();
        System.out.println("Fetched " + docs.size() + " docs:");
        for (QueryDocumentSnapshot d : docs) {
            Map<String, Object> data = d.getData();
            data.put("id", d.getId());
            System.out.println(" - id=" + d.getId() + " data=" + data);
        }
    }

    public Timestamp getWatermark() throws Exception {
        DocumentSnapshot snap = db.collection("system").document("meta").get().get();
        if (!snap.exists()) return null;
        Object ts = snap.get("lastProcessedAt");
        if (ts instanceof Timestamp) {
            return (Timestamp) ts;
        }
        return null;
    }

    public void updateWatermark(Timestamp timestamp, String id) throws Exception {
        Map<String, Object> meta = new HashMap<>();
        meta.put("lastProcessedAt", timestamp);
        meta.put("lastProcessedId", id);
        meta.put("updatedAt", FieldValue.serverTimestamp());
        db.collection("system").document("meta").set(meta, SetOptions.merge()).get();
    }

    public List<Map<String, Object>> fetchNewItems(Timestamp lastProcessedAt, int limit) throws Exception {
        Query query = db.collection("items")
                .orderBy("timestamp", Query.Direction.DESCENDING)
                .limit(limit);

        if (lastProcessedAt != null) {
            query = query.whereGreaterThan("timestamp", lastProcessedAt);
        }

        List<QueryDocumentSnapshot> docs = query.get().get().getDocuments();
        List<Map<String, Object>> results = new ArrayList<>();
        for (QueryDocumentSnapshot doc : docs) {
            Map<String, Object> data = doc.getData();
            data.put("id", doc.getId());
            results.add(data);
        }
        return results;
    }

    // Date is Firestore Timestamp here
    public List<QueryDocumentSnapshot> findOppositeTypeItems(
            String type,
            String category,
            String title,
            String stationOrTrain,
            Timestamp date
    ) throws Exception {

        String oppositeType = type.equalsIgnoreCase("lost") ? "found" : "lost";

        String catNorm = norm(category);
        String titleNorm = norm(title);
        String stationNorm = norm(stationOrTrain);

        Query query = db.collection("items")
                .whereEqualTo("type", oppositeType)
                .whereEqualTo("category_norm", catNorm)
                .whereEqualTo("title_norm", titleNorm)
                .whereEqualTo("stationOrTrain_norm", stationNorm)
                .whereEqualTo("date", date);

        return query.get().get().getDocuments();
    }

    public boolean isMatchAlreadyStored(String item1Id, String item2Id) throws Exception {
        Query query = db.collection("matches")
                .whereIn("item1Id", Arrays.asList(item1Id, item2Id))
                .whereIn("item2Id", Arrays.asList(item1Id, item2Id));
        return !query.get().get().isEmpty();
    }

    public void saveMatch(String item1Id, String item2Id) throws Exception {
        Map<String, Object> matchDoc = new HashMap<>();
        matchDoc.put("item1Id", item1Id);
        matchDoc.put("item2Id", item2Id);
        matchDoc.put("matchedAt", FieldValue.serverTimestamp());
        db.collection("matches").add(matchDoc).get();
    }

    private String norm(String s) {
        return s == null ? "" : s.trim().toLowerCase();
    }
    
    public Map<String, Object> getItemById(String itemId) throws Exception {
        DocumentSnapshot d = db.collection("items").document(itemId).get().get();
        if (!d.exists()) return null;
        Map<String, Object> data = d.getData();
        if (data == null) data = new HashMap<>();
        data.put("id", d.getId());
        return data;
    }

}
