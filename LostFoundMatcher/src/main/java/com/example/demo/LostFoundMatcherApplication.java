package com.example.demo;

import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

import com.example.demo.repo.FirestoreTestRepository;

@EnableScheduling
@SpringBootApplication
public class LostFoundMatcherApplication implements CommandLineRunner {

  private final FirestoreTestRepository testRepo;

  public LostFoundMatcherApplication(FirestoreTestRepository testRepo) {
    this.testRepo = testRepo;
  }

  public static void main(String[] args) {
    SpringApplication.run(LostFoundMatcherApplication.class, args);
  }

  @Override
  public void run(String... args) throws Exception {
    try {
      testRepo.printLatestItems(5);
    } catch (Exception e) {
      System.err.println("Error reading Firestore: " + e.getMessage());
      e.printStackTrace();
    }
  }
}
