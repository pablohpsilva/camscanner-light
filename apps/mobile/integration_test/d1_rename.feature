Feature: Rename a document

  Scenario: Rename a document from the library list
    Given a document with a real page image was saved to persistent storage earlier
    When the app launches reading that same storage
    And I open the rename menu for the first document
    And I rename the document to {'Field Notes'}
    Then I see {'Field Notes'} text
