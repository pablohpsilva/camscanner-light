Feature: Print a document

  Scenario: Print the open document
    Given a document with a real page image was saved to persistent storage earlier
    When the app launches reading that same storage
    And I open the first document
    And I print the document
    Then I see the print confirmation
