Feature: I1 Export page as image

  Scenario: Exporting the open page saves it as an image
    Given a document with a real page image was saved to persistent storage earlier
    When the app launches reading that same storage
    And I open the first document
    And I export the page as an image
    Then I see the image export confirmation
