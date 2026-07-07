Feature: Share a document

  Scenario: Share the saved document's PDF from the library
    Given a document with a real page image was saved to persistent storage earlier
    When the app launches reading that same storage
    And I share the first document
    Then the document is handed to the share sheet
