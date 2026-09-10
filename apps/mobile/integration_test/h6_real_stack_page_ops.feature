Feature: H6 Page operations against REAL storage

  H3 and H4 already cover reorder and delete, but they open the page viewer with
  a FakeDocumentRepository — so the real PageOrderingService never runs and its
  deletePage/reorderPages bodies measured 0% e2e coverage despite "having" tests.
  These scenarios drive the SAME user actions through the real stack: a seeded
  Drift database, real JPEGs on disk, and the real app booted against them.

  Scenario: Deleting a page updates the real database
    Given a document with 2 real page images was saved to persistent storage earlier
    When the app launches reading that same storage
    And I open the first document
    And I delete the current page
    Then the document has 1 page

  # Going back to home is REQUIRED before the second launch: an in-test
  # relaunch pumps into the existing element tree, so the Navigator keeps its
  # route stack and the relaunched UI only shows home if home is already on top.
  Scenario: A deleted page stays deleted after a relaunch
    Given a document with 2 real page images was saved to persistent storage earlier
    When the app launches reading that same storage
    And I open the first document
    And I delete the current page
    And I go back to home from the page viewer
    And the app launches reading that same storage
    And I open the first document
    Then the document has 1 page

  Scenario: Reordering pages persists to the real database
    Given a document with 2 real page images was saved to persistent storage earlier
    When the app launches reading that same storage
    And I open the first document
    And the second page thumbnail is dragged to the first position
    Then the first visible page is position 2
