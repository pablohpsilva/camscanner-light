Feature: H5 Multi-page PDF export

  Scenario: Exporting a three-page document produces a three-page PDF
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I capture and accept the first page
    And I capture and accept the second page
    And I capture and accept the third page
    And I tap Done
    And I open the first document
    And I export the open document to PDF
    Then the PDF preview opens
    And the exported PDF has 3 pages
