Feature: Rotate a page

  Scenario: Rotate the open page
    Given a document with a real page image was saved to persistent storage earlier
    When the app launches reading that same storage
    And I open the first document
    And I rotate the page
    Then I see the page viewer
