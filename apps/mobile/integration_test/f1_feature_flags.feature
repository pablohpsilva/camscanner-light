Feature: Build-time feature flags hide disabled actions
  Scenario: A build with the print feature disabled hides the Print action
    Given a document with a real page image was saved to persistent storage earlier
    When the app launches with the print feature disabled
    And I open the first document
    Then I see the page viewer
    When I open the share menu
    Then I do not see the print action
