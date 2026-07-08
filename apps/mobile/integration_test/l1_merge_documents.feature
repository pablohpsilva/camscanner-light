Feature: Merge documents

  Scenario: Merge another document into the open one
    Given two documents with real page images were saved to persistent storage earlier
    When the app launches reading that same storage
    And I open the first document
    And I merge the other document
    Then I see two page thumbnails
