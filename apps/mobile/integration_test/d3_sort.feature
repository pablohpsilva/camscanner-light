Feature: Sort the library
  Scenario: Switch the library sort to name
    Given a document with a real page image was saved to persistent storage earlier
    When the app launches reading that same storage
    And I tap the sort chip {'name'}
    Then I see the sort chip {'name'} is active
