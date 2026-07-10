Feature: Library grid view
  Scenario: Switch the library to grid and see a saved document
    Given a document with a real page image was saved to persistent storage earlier
    When the app launches reading that same storage
    And I switch to grid view
    Then I see the document in grid
