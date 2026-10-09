from django.test import TestCase


class IndexTest(TestCase):
    def test_index_returns_200(self):
        response = self.client.get('/demo/')
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'Agenda')
