Feature: Legal documents

  Terms of Service, Privacy Policy and FAQ are readable from Settings, offline,
  in the user's own language. Translations carry a notice that the English
  version prevails.

  Scenario: The terms disclaim liability and place responsibility on the user
    Given the app is launched with empty storage and mocked preferences
    When I open settings from home
    And I open the terms of service
    Then the document disclaims all warranties
    And the document says I am responsible for what I scan

  Scenario: The privacy policy warns that feedback is public
    Given the app is launched with empty storage and mocked preferences
    When I open settings from home
    And I open the privacy policy
    Then the document warns that feedback is public

  Scenario: FAQ answers are hidden until a question is tapped
    Given the app is launched with empty storage and mocked preferences
    When I open settings from home
    And I open the faq
    And I expand the first question
    Then the answer is shown

  Scenario: A translated document says the English version prevails
    Given the app is launched with empty storage and mocked preferences
    When I open settings from home
    And I choose the Spanish language
    And I open the terms of service
    Then the English prevails notice is shown

  Scenario: Tapping a sibling document link opens that document in-app
    Given the app is launched with empty storage and mocked preferences
    When I open settings from home
    And I open the terms of service
    And I tap the privacy policy link
    Then the document warns that feedback is public
