Feature: Split a document

  Scenario: Split after the first page
    Given a document with 2 real page images was saved to persistent storage earlier
    When the app launches reading that same storage
    And I open the first document
    And I split after the first page
    Then I see the split confirmation
