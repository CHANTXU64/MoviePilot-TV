"""Check saved source-fixture evidence, not a Swift build or a live backend."""
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "docs" / "compatibility-evidence"


class BackendContractEvidenceTests(unittest.TestCase):
    tags = ("v3.0.4", "v3.0.5", "v3.0.10-1", "v3.1.0")

    def fixtures(self):
        return [json.loads((EVIDENCE / f"{tag}.json").read_text()) for tag in self.tags]

    def test_provenance_is_explicit_and_pinned(self):
        for tag, fixture in zip(self.tags, self.fixtures()):
            evidence = fixture["provenance"]
            self.assertEqual(evidence["backend_tag"], tag)
            self.assertEqual(len(evidence["backend_commit"]), 40)
            self.assertTrue(evidence["not_live_backend"])
            self.assertEqual(fixture["checks"]["fork_serialization"], "passed")
            self.assertEqual(fixture["checks"]["write_projection_and_clears"], "passed")

    def test_v304_fork_fails_after_stub_creation_and_fixed_releases_retain_id(self):
        for tag, fixture in zip(self.tags, self.fixtures()):
            fork = fixture["fork"]
            self.assertEqual(fork["stub_creation_count"], 1)
            self.assertEqual(fork["status"], 500 if tag == "v3.0.4" else 200)
            if tag != "v3.0.4":
                self.assertEqual(fork["body"]["data"]["id"], 42)

    def test_same_subscription_contract_is_shared_without_version_copies(self):
        fixtures = self.fixtures()
        schema = fixtures[0]["provenance"]["source_sha256"]["app/schemas/subscribe.py"]
        detail = fixtures[0]["subscription_detail_response"]["data"]
        for fixture in fixtures:
            self.assertEqual(fixture["provenance"]["source_sha256"]["app/schemas/subscribe.py"], schema)
            self.assertEqual(fixture["subscription_detail_response"]["data"], detail)
        self.assertEqual(detail["media_category_id"], "stable-category")

    def test_writable_projection_preserves_explicit_clear_and_excludes_system_facts(self):
        for fixture in self.fixtures():
            projection = fixture["subscription_update_writable_projection"]
            self.assertFalse(set(projection) & set(fixture["subscription_public_write_excluded_fields"]))
            self.assertIsNone(projection["media_category_id"])
            self.assertIsNone(projection["quality"])
            self.assertEqual(projection["sites"], [])
            self.assertEqual(projection["filter_groups"], [])


if __name__ == "__main__":
    unittest.main()
