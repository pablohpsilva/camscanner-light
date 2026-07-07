Feature: Export all pages as images

  Scenario: Exporting all pages of the open document saves them as images
    Given a document with a real page image was saved to persistent storage earlier
    When the app launches reading that same storage
    And I open the first document
    And I export all pages as images
    Then I see the all images export confirmation
