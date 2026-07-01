Feature: I1 Export page as image

  Scenario: Exporting the open page saves it as an image
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I capture and accept the first page
    And I tap Done
    And I open the first document
    And I export the page as an image
    Then I see the image export confirmation
