Feature: Preview a document as PDF

  Scenario: Preview a saved document as a PDF
    Given a document with a real page image was saved to persistent storage earlier
    When the app launches reading that same storage
    And I open the first document
    And I export the open document to PDF
    Then the PDF preview opens
