Feature: iOS tip jar

  Scenario: Successful tip shows a thank-you
    Given the tip jar has products
    When I tap the small tip
    Then I see the tip thank-you dialog

  Scenario: Store unavailable
    Given the tip jar has no products
    Then I see the tip unavailable message
