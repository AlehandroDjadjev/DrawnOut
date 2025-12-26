import unittest

from lesson_pipeline.services.script_writer import ScriptWriterService


class ScriptWriterImageRequestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = ScriptWriterService()

    def test_parses_explicit_image_requests(self):
        timeline = {
            "segments": [],
            "image_requests": [
                {
                    "id": "img_1",
                    "prompt": "labeled chloroplast diagram",
                    "placement": {
                        "x": 0.1,
                        "y": 0.2,
                        "width": 0.3,
                        "height": 0.25,
                        "scale": 1.05,
                    },
                    "filename_hint": "chloroplast-diagram",
                    "style": "diagram",
                }
            ],
        }

        requests = self.service._build_image_requests(timeline)

        self.assertEqual(len(requests), 1)
        req = requests[0]
        self.assertEqual(req.id, "img_1")
        self.assertEqual(req.prompt, "labeled chloroplast diagram")
        self.assertIsNotNone(req.placement)
        self.assertAlmostEqual(req.placement.x, 0.1)
        self.assertAlmostEqual(req.placement.width, 0.3)
        self.assertAlmostEqual(req.placement.scale or 0, 1.05)
        self.assertEqual(req.filename_hint, "chloroplast-diagram")
        self.assertEqual(req.style, "diagram")

    def test_derives_image_requests_from_drawing_actions(self):
        timeline = {
            "segments": [
                {
                    "drawing_actions": [
                        {
                            "type": "sketch_image",
                            "prompt": "cell membrane illustration",
                            "tag_id": "img_action_1",
                            "placement": {
                                "x": 0.3,
                                "y": 0.4,
                                "width": 0.2,
                                "height": 0.2,
                            },
                        }
                    ]
                }
            ]
        }

        requests = self.service._build_image_requests(timeline)

        self.assertEqual(len(requests), 1)
        req = requests[0]
        self.assertEqual(req.id, "img_action_1")
        self.assertEqual(req.prompt, "cell membrane illustration")
        self.assertIsNotNone(req.placement)
        self.assertAlmostEqual(req.placement.x, 0.3)
        self.assertAlmostEqual(req.placement.height, 0.2)


if __name__ == "__main__":
    unittest.main()











