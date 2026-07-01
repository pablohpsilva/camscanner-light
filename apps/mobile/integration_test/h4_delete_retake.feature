Feature: H4 Delete page

  Scenario: Deleting one page of a two-page document leaves one page
    Given the page viewer is open with 2 pages
    When I delete the current page
    Then the document has 1 page
