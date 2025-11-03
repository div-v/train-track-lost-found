package com.example.demo.job;

import com.example.demo.repo.FirestoreTestRepository;
import com.example.demo.service.NotificationService;
import com.example.demo.service.NLPService;
import com.example.demo.service.ImageMatchService;
import com.google.cloud.Timestamp;
import com.google.cloud.firestore.QueryDocumentSnapshot;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

@Component
public class NewItemDetectorJob {
    private static final Logger log = LoggerFactory.getLogger(NewItemDetectorJob.class);
    private final FirestoreTestRepository repo;
    private final NotificationService notificationService;
    private final NLPService nlpService;
    private final ImageMatchService imageMatchService;

    private static final double NLP_THRESHOLD = 0.7; // adjust as needed
    private static final double IMAGE_THRESHOLD = 0.85; // adjust as needed
    private static final int FETCH_LIMIT = 50;

    public NewItemDetectorJob(FirestoreTestRepository repo,
                              NotificationService notificationService,
                              NLPService nlpService,
                              ImageMatchService imageMatchService) {
        this.repo = repo;
        this.notificationService = notificationService;
        this.nlpService = nlpService;
        this.imageMatchService = imageMatchService;
    }

    @Scheduled(cron = "0 */2 * * * *")
    public void detectAndMatch() {
        try {
            Timestamp lastProcessedAt = repo.getWatermark();
            log.info("Last processed timestamp: {}", lastProcessedAt);

            List<Map<String, Object>> newItems = repo.fetchNewItems(lastProcessedAt, FETCH_LIMIT);
            if (newItems.isEmpty()) {
                log.info("No new items found");
                return;
            }
            log.info("Found {} new items", newItems.size());

            Timestamp newestTimestamp = null;
            String newestId = null;

            for (Map<String, Object> item : newItems) {
                String newItemId = asString(item.get("id"));
                String type = asString(item.get("type"));
                String category = asString(item.get("category"));
                String title = asString(item.get("title"));
                String stationOrTrain = asString(item.get("stationOrTrain"));
                Timestamp ts = (Timestamp) item.get("timestamp");
                Timestamp date = (Timestamp) item.get("date"); // Firestore Timestamp

                if (type.isBlank() || category.isBlank() || title.isBlank() || stationOrTrain.isBlank() || date == null) {
                    log.warn("Skipping item {} due to missing required fields", newItemId);
                    continue;
                }

                List<QueryDocumentSnapshot> possibleMatches =
                        repo.findOppositeTypeItems(type, category, title, stationOrTrain, date);

                for (QueryDocumentSnapshot matchDoc : possibleMatches) {
                    String matchId = matchDoc.getId();
                    if (matchId.equals(newItemId)) continue;

                    if (repo.isMatchAlreadyStored(newItemId, matchId)) {
                        log.info("Skipping existing match: {} ↔ {}", newItemId, matchId);
                        continue;
                    }

                    try {
                        Map<String, Object> a = repo.getItemById(newItemId);
                        Map<String, Object> b = repo.getItemById(matchId);
                        if (a == null || b == null) {
                            log.warn("One of the items is missing in Firestore: {} or {}", newItemId, matchId);
                            continue;
                        }

                        // ---- DESCRIPTION SIMILARITY ----
                        String descA = asString(a.get("description"));
                        String descB = asString(b.get("description"));
                        if (descA.isBlank() || descB.isBlank()) {
                            log.info("Skipping {} ↔ {}: missing description(s)", newItemId, matchId);
                            continue;
                        }

                        double nlpSimilarity;
                        try {
                            nlpSimilarity = nlpService.getSimilarity(descA, descB);
                        } catch (Exception ex) {
                            log.error("NLP service failed for {} ↔ {} — skipping. Error: {}", newItemId, matchId, ex.getMessage());
                            continue;
                        }

                        if (Double.isNaN(nlpSimilarity) || nlpSimilarity < NLP_THRESHOLD) {
                            log.info("Skipping {} ↔ {} due to low NLP similarity: {} (threshold {})",
                                    newItemId, matchId, nlpSimilarity, NLP_THRESHOLD);
                            continue;
                        }

                        // ---- IMAGE SIMILARITY ----
                        String imageA = asString(a.get("photoUrl"));
                        String imageB = asString(b.get("photoUrl"));
                        if (imageA.isBlank() || imageB.isBlank()) {
                            log.info("Skipping {} ↔ {}: missing photoUrl(s)", newItemId, matchId);
                            continue;
                        }

                        double imageSimilarity;
                        try {
                            imageSimilarity = imageMatchService.getSimilarity(imageA, imageB);
                        } catch (Exception ex) {
                            log.error("Image service failed for {} ↔ {} — skipping. Error: {}", newItemId, matchId, ex.getMessage());
                            continue;
                        }

                        if (imageSimilarity < IMAGE_THRESHOLD) {
                            log.info("Skipping {} ↔ {} due to low IMAGE similarity: {} (threshold {})",
                                    newItemId, matchId, imageSimilarity, IMAGE_THRESHOLD);
                            continue;
                        }

                        // ---- SAVE MATCH ----
                        try {
                            repo.saveMatch(newItemId, matchId);
                            log.info("Stored new match: {} ↔ {} with NLP similarity {} and IMAGE similarity {}",
                                    newItemId, matchId, nlpSimilarity, imageSimilarity);
                        } catch (Exception e) {
                            log.error("Failed to save match {} ↔ {}: {}", newItemId, matchId, e.getMessage());
                            continue;
                        }

                        // ---- NOTIFICATIONS ----
                        String ownerA = asString(a.get("postedBy"));
                        String ownerB = asString(b.get("postedBy"));
                        String titleA = asString(a.get("title"));
                        String titleB = asString(b.get("title"));

                        if (!ownerA.isBlank()) {
                            notificationService.sendToUser(ownerA, "Match found!", "A found item matches your lost post: " + titleA);
                        } else {
                            log.warn("Missing postedBy on item {}", newItemId);
                        }

                        if (!ownerB.isBlank()) {
                            notificationService.sendToUser(ownerB, "Match found!", "A lost item matches your found post: " + titleB);
                        } else {
                            log.warn("Missing postedBy on item {}", matchId);
                        }

                    } catch (Exception e) {
                        log.error("Failed to process match {} ↔ {}", newItemId, matchId, e);
                    }
                }

                if (ts != null && (newestTimestamp == null || ts.compareTo(newestTimestamp) > 0)) {
                    newestTimestamp = ts;
                    newestId = newItemId;
                }
            }

            if (newestTimestamp != null) {
                repo.updateWatermark(newestTimestamp, newestId);
                log.info("Updated watermark to timestamp: {}, id: {}", newestTimestamp, newestId);
            }

        } catch (Exception e) {
            log.error("Failed to detect/match new items", e);
        }
    }

    private String asString(Object o) {
        return o == null ? "" : String.valueOf(o);
    }
}
