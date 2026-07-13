Feature: Change a saved page's filter
  Scenario: Apply a grayscale filter to a saved page without error
    Given a document with a real page image was saved to persistent storage earlier
    When the app launches reading that same storage
    And I open the first document
    Then I see the page viewer
    When I tap the filter button
    And I tap the grayscale filter tile
    And I tap save on the filter screen
    Then I see the page viewer
