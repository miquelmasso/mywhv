import 'package:flutter_test/flutter_test.dart';
import 'package:mywhv/services/careers_extractor.dart';

void main() {
  test('finds same-site and external careers links on verified homepage', () {
    final links = CareersExtractor.constructionCareerLinksFromHomepage(
      'https://example-mining.com.au',
      '''
      <nav>
        <a href="/contact">Contact</a>
        <a href="/careers/current-vacancies">Careers</a>
        <a href="https://jobs.example-ats.com/example-mining">Jobs</a>
      </nav>
      ''',
    );

    expect(
      links.first,
      'https://example-mining.com.au/careers/current-vacancies',
    );
    expect(links, contains('https://jobs.example-ats.com/example-mining'));
  });

  test('rejects social links even when their path contains jobs', () {
    final links = CareersExtractor.constructionCareerLinksFromHomepage(
      'https://example-mining.com.au',
      '<a href="https://linkedin.com/jobs/example">Jobs</a>',
    );

    expect(links, isEmpty);
  });
}
