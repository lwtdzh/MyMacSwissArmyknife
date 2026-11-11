func expectCounters(_ actual: Counters, download: UInt64, upload: UInt64, _ message: String) {
    guard actual.download == download, actual.upload == upload else {
        fatalError("\(message): got \(actual.download)/\(actual.upload), expected \(download)/\(upload)")
    }
}

let header = ",bytes_in,bytes_out,\r\n"

do {
    var parser = NetworkDeltaParser()
    expectCounters(
        parser.consume(Data((header + "uploadDownload.32834,51750,33566902,\r\n").utf8)),
        download: 0, upload: 0, "Startup totals must not become traffic"
    )
    expectCounters(
        parser.consume(Data((header + "uploadDownload.32834,0,4723674,\r\n"
            + header + "uploadDownload.32834,11547,4658596,\r\n").utf8)),
        download: 11547, upload: 9382270, "Each native delta must count even when its value decreases"
    )
}

do {
    var parser = NetworkDeltaParser()
    _ = parser.consume(Data((header + "old.1,1000,1000,\n").utf8))
    expectCounters(
        parser.consume(Data((header + "new.2,37,100000,\n").utf8)),
        download: 37, upload: 100000, "A newly observed process must count immediately"
    )
    expectCounters(parser.consume(Data(header.utf8)),
                   download: 0, upload: 0, "A frame with no connections must add zero")
    expectCounters(parser.consume(Data((header + "another.3,11,50000,\n").utf8)),
                   download: 11, upload: 50000, "Closed processes must not erase new process traffic")
}

let stream = Data((header + "baseline.1,999999,999999,\r\n"
    + header + "中国移动云.2,23,4500000,\r\n"
    + "forwarder.3,41,89,\r\n"
    + header + "中国移动云.2,3,4300000,\r\n").utf8)
for chunkSize in [1, 2, 7, 64, stream.count] {
    var parser = NetworkDeltaParser()
    var total = Counters()
    var offset = 0
    while offset < stream.count {
        let end = min(offset + chunkSize, stream.count)
        let delta = parser.consume(stream.subdata(in: offset..<end))
        total.download += delta.download
        total.upload += delta.upload
        offset = end
    }
    expectCounters(total, download: 67, upload: 8800089,
                   "Fragmented headers, UTF-8 names and multiple frames: chunk \(chunkSize)")
}

do {
    var parser = NetworkDeltaParser()
    let input = "orphan.1,999,999,\n" + header + header
        + "bad.2,not-a-number,10,\n"
        + "bad.3,-1,10,\n"
        + "valid.4,5,7,\n"
        + "partial.5,11,13,"
    expectCounters(parser.consume(Data(input.utf8)),
                   download: 5, upload: 7, "Malformed and incomplete rows must not add traffic")
    expectCounters(parser.consume(Data("\n".utf8)),
                   download: 11, upload: 13, "An incomplete row must count once when completed")
    expectCounters(parser.consume(Data()),
                   download: 0, upload: 0, "Consumed rows must not replay")
}

FileHandle.standardOutput.write(Data("Network delta parser regression tests passed.\n".utf8))
