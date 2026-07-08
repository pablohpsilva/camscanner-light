Feature: Re-edit crop
  Scenario: User re-adjusts corners on a saved document and sees the updated page
    Given a document with a real page image was saved to persistent storage earlier
    When the app launches reading that same storage
    And I open the first document
    Then I see the page viewer
    When I tap the edit crop button
    Then I see the crop overlay
    When I drag the top left crop corner
    And I tap Accept on the viewer
    Then I see the page viewer
