Feature: H1 Add multiple pages to a document

  Scenario: Accepting first page keeps camera open
    Given the camera screen is open
    When I capture and accept the first page
    Then the camera screen shows the Done button

  Scenario: Two pages are saved to the same document
    Given the camera screen is open
    When I capture and accept the first page
    And I capture and accept the second page
    And I tap Done
    Then the document has 2 pages
