Feature: H5 Multi-page PDF export

  Scenario: Exporting a three-page document produces a three-page PDF
    Given a document with 3 real page images was saved to persistent storage earlier
    When the app launches reading that same storage
    And I open the first document
    And I export the open document to PDF
    Then the PDF preview opens
    And the exported PDF has 3 pages
