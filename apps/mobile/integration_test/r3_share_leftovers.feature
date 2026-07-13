Feature: Share leftovers surface as not-yet-available

  Scenario: Fax on a document is not available yet
    Given a document was saved to persistent storage earlier
    And the app launches with fax enabled reading that same storage
    When I open the first document's menu
    And I tap the Fax action
    Then I see the message {'Fax isn\'t available yet'}
