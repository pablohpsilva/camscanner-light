Feature: C5R Home swipe actions against REAL storage

  The host swipe BDD (test/bdd/document_swipe_actions.feature) pumps
  DocumentsListView directly and asserts a recorded callback fired, so
  HomeScreen's real _copyText / _deleteDocument handlers never ran — they were
  uncovered by BOTH suites. These drive the same swipes against the real app
  over a seeded Drift database.

  Scenario: Copying text via swipe copies the document's recognized text
    Given a saved document with recognized text {'HELLO WORLD'}
    When the app launches reading that same storage
    And I swipe the first document right
    And I tap the copy text swipe action
    Then I see the copy text confirmation

  # The empty branch exists so an empty clipboard is never silently written.
  Scenario: Copying from a document with no text says so instead of copying
    Given a document was saved to persistent storage earlier
    When the app launches reading that same storage
    And I swipe the first document right
    And I tap the copy text swipe action
    Then I see the no text to copy message

  Scenario: Deleting via swipe removes the document from real storage
    Given a document was saved to persistent storage earlier
    When the app launches reading that same storage
    And I swipe the first document left
    And I tap the delete swipe action
    And I confirm the delete dialog
    Then the document is gone from the home
