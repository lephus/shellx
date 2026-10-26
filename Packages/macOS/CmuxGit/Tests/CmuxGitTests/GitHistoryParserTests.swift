import Foundation
import Testing
@testable import CmuxGit

@Suite struct GitHistoryParserTests {
    @Test func parsesLogRecordsWithMergesRootAndOddSubjects() {
        let raw = [
            "a1\u{1f}b2 c3\u{1f}develop\u{1f}Phu.le\u{1f}p@x.dev\u{1f}2026-10-26T11:52:00+07:00\u{1f}2026-10-26T11:53:00+07:00\u{1f}Merge <img onerror=x> 🎉\u{1e}",
            "\nb2\u{1f}\u{1f}origin/main\u{1f}A B\u{1f}a@b.c\u{1f}2026-10-25T00:00:00Z\u{1f}2026-10-25T00:00:00Z\u{1f}root\u{1e}\n",
        ].joined()
        let commits = GitHistoryParser.commits(fromLog: Data(raw.utf8))
        #expect(commits.count == 2)
        #expect(commits[0].parents == ["b2", "c3"])
        #expect(commits[0].subject == "Merge <img onerror=x> 🎉")
        #expect(commits[1].parents.isEmpty)
        #expect(commits[1].source == "origin/main")
    }

    @Test func parsesRefsPeelsAnnotatedTagsAndSkipsRemoteHead() {
        let raw = "refs/heads/main\u{1f}aaa\u{1f}\u{1e}refs/remotes/origin/HEAD\u{1f}aaa\u{1f}\u{1e}"
            + "refs/remotes/origin/feature/x\u{1f}bbb\u{1f}\u{1e}refs/tags/v1.0\u{1f}tagobj\u{1f}ccc\u{1e}"
        let refs = GitHistoryParser.refs(fromForEachRef: Data(raw.utf8))
        #expect(refs.map(\.name) == ["main", "origin/feature/x", "v1.0"])
        #expect(refs.map(\.kind) == [.localBranch, .remoteBranch, .tag])
        #expect(refs[2].target == "ccc")
    }

    @Test func parsesFileChangesWithRenameBinaryAndOddPaths() {
        let nameStatus = "M\u{0}dir/a file.txt\u{0}R100\u{0}old/ü.swift\u{0}new/ü.swift\u{0}A\u{0}img.png\u{0}A\u{0}line\nbreak.txt\u{0}"
        let numstat = "3\t1\tdir/a file.txt\u{0}0\t0\t\u{0}old/ü.swift\u{0}new/ü.swift\u{0}-\t-\timg.png\u{0}1\t0\tline\nbreak.txt\u{0}"
        let files = GitHistoryParser.fileChanges(nameStatusZ: Data(nameStatus.utf8), numstatZ: Data(numstat.utf8))
        #expect(files.map(\.path) == ["dir/a file.txt", "new/ü.swift", "img.png", "line\nbreak.txt"])
        #expect(files[1].status == .renamed && files[1].oldPath == "old/ü.swift")
        #expect(files[2].additions == nil && files[2].deletions == nil)
        #expect(files[0].additions == 3 && files[0].deletions == 1)
    }

    @Test func countsWorkingTreeStatus() {
        let raw = " M a.txt\u{0}A  b.txt\u{0}?? c.txt\u{0} D d.txt\u{0}R  e.txt\u{0}old-e.txt\u{0}"
        let status = GitHistoryParser.workingTreeStatus(porcelainV1Z: Data(raw.utf8))
        #expect(status == GitHistoryWorkingTreeStatus(added: 2, modified: 2, deleted: 1))
        #expect(GitHistoryParser.workingTreeStatus(porcelainV1Z: Data()).isClean)
    }
}
