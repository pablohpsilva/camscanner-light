Feature: Documents persist across an app restart

  Scenario: A document saved earlier is listed after a fresh launch
    Given a document was saved to persistent storage earlier
    When the app launches reading that same storage
    Then I see a saved document on the home
