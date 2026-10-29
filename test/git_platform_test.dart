import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/platforms/git_platform.dart';

void main() {
  test('guessPlatform recognises known hosts case-insensitively', () {
    expect(guessPlatform('https://GitHub.com/a/b'), GitPlatform.github);
    expect(guessPlatform('https://gitee.com/a/b'), GitPlatform.gitee);
    expect(guessPlatform('https://gitcode.com/a/b'), GitPlatform.gitcode);
    expect(guessPlatform('https://atomgit.com/a/b'), GitPlatform.atomgit);
    expect(guessPlatform('https://gitlab.com/a/b'), GitPlatform.gitlab);
  });

  test('self-hosted and unknown hosts fall back to other', () {
    expect(guessPlatform('https://git.example.com/a/b'), GitPlatform.other);
    expect(
      guessPlatform('https://gitea.mycompany.internal/team/notes'),
      GitPlatform.other,
    );
  });

  test('other has no webBase so short-form URLs are not built', () {
    expect(GitPlatform.other.webBase, isEmpty);
    for (final platform in GitPlatform.values) {
      if (platform == GitPlatform.other) continue;
      expect(platform.webBase, isNotEmpty, reason: '${platform.name} 可拼接短地址');
    }
  });
}
