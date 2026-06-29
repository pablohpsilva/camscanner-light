Feature: View and delete a document

  Scenario: Open a saved document, view its page, then delete it
    Given a document was saved to persistent storage earlier
    When the app launches reading that same storage
    And I open the first document
    And I delete the open document
    Then the document is gone from the home
