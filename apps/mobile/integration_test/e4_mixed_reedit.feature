Feature: Mixed re-edit of a page
  Scenario: Rotate and crop repeatedly without error
    Given a document with a real page image was saved to persistent storage earlier
    When the app launches reading that same storage
    And I open the first document
    Then I see the page viewer
    When I rotate the page
    And I tap the edit crop button
    Then I see the crop overlay
    When I drag the top left crop corner
    And I tap Accept on the viewer
    Then I see the page viewer
    When I rotate the page
    And I tap the edit crop button
    Then I see the crop overlay
    When I drag the top left crop corner
    And I tap Accept on the viewer
    Then I see the page viewer
