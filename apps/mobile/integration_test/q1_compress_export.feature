Feature: Q1 Compress / export quality

  Scenario: Choosing a quality when exporting a page as an image
    Given a document with a real page image was saved to persistent storage earlier
    When the app launches reading that same storage
    And I open the first document
    And I export the page as an image at Medium quality
    Then I see the image export confirmation
