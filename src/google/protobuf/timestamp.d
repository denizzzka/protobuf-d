module google.protobuf.timestamp;

import std.datetime : DateTime, SysTime, unixTimeToStdTime, UTC;
import std.exception : enforce;
import std.json : JSONValue;
import google.protobuf;

struct Timestamp
{
    private struct _Message
    {
      @Proto(1) long seconds = protoDefaultValue!long;
      @Proto(2) int nanos = protoDefaultValue!int;
    }

    private static immutable defaultTimestampValue = SysTime(DateTime(1970, 1, 1, 0, 0, 0), UTC());
    SysTime timestamp = defaultTimestampValue;

    alias timestamp this;

    auto toProtobuf()
    {
        long epochDelta = timestamp.stdTime - unixTimeToStdTime(0);

        return _Message(epochDelta / 1_000_000_0, epochDelta % 1_000_000_0 * 100).toProtobuf;
    }

    Timestamp fromProtobuf(R)(ref R inputRange)
    {
        auto message = inputRange.fromProtobuf!_Message;
        long epochDelta = message.seconds * 1_000_000_0 + message.nanos / 100;
        timestamp.stdTime = epochDelta + unixTimeToStdTime(0);

        return this;
    }

    JSONValue toJSONValue()()
    {
        import std.format : format;
        import google.protobuf.json_encoding;

        validateTimestamp;

        auto utc = timestamp.toUTC;
        auto fractionalDigits = utc.fracSecs.total!"nsecs";
        auto fractionalLength = 9;

        foreach (i; 0 .. 3)
        {
            if (fractionalDigits % 1000 != 0)
                break;
            fractionalDigits /= 1000;
            fractionalLength -= 3;
        }

        if (fractionalDigits)
            return "%04d-%02d-%02dT%02d:%02d:%02d.%0*dZ".format(utc.year, utc.month, utc.day, utc.hour, utc.minute,
                utc.second, fractionalLength, fractionalDigits).toJSONValue;
        else
            return "%04d-%02d-%02dT%02d:%02d:%02dZ".format(utc.year, utc.month, utc.day, utc.hour, utc.minute,
                utc.second).toJSONValue;
    }

    Timestamp fromJSONValue()(JSONValue value)
    {
        import core.time : dur;
        import std.algorithm : skipOver;
        import std.conv : ConvException, to;
        import std.datetime : DateTime, DateTimeException, Month, SimpleTimeZone, UTC;
        import std.json : JSON_TYPE;
        import std.regex : matchAll, regex;
        import std.string : leftJustify;
        import google.protobuf.json_decoding : fromJSONValue;

        if (value.type == JSON_TYPE.NULL)
        {
            timestamp = defaultTimestampValue;
            return this;
        }

        auto match = value.fromJSONValue!string.matchAll(
                        `^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(.\d*)?((Z)|([+-])(\d{2}):(\d{2}))$`);
        enforce!ProtobufException(match, "Invalid timestamp JSON encoding");

        auto yearPart = match.front[1];
        auto monthPart = match.front[2];
        auto dayPart = match.front[3];
        auto hourPart = match.front[4];
        auto minutePart = match.front[5];
        auto secondPart = match.front[6];
        auto fracSecsPart = match.front[7];
        fracSecsPart.skipOver('.');

        try
        {
            import std.file: append;
            if (match.front[8] == "Z")
            {
                timestamp = SysTime(
                                DateTime(yearPart.to!short, monthPart.to!ubyte.to!Month, dayPart.to!ubyte,
                                    hourPart.to!ubyte, minutePart.to!ubyte, secondPart.to!ubyte),
                                dur!"nsecs"(fracSecsPart.leftJustify(9, '0').to!uint), UTC());
            }
            else
            {
                auto tz_offset = dur!"hours"(match.front[11].to!uint) + dur!"minutes"(match.front[12].to!uint);
                if (match.front[10] == "-")
                    tz_offset = -tz_offset;
                timestamp = SysTime(
                                DateTime(yearPart.to!short, monthPart.to!ubyte.to!Month, dayPart.to!ubyte,
                                    hourPart.to!ubyte, minutePart.to!ubyte, secondPart.to!ubyte),
                                dur!"nsecs"(fracSecsPart.leftJustify(9, '0').to!uint),
                                new immutable SimpleTimeZone(tz_offset));
            }

            validateTimestamp;
            return this;
        }
        catch (ConvException exception)
        {
            throw new ProtobufException(exception.msg);
        }
        catch (DateTimeException exception)
        {
            throw new ProtobufException(exception.msg);
        }
    }

    void validateTimestamp()
    {
        auto year = timestamp.toUTC.year;
        enforce!ProtobufException(0 < year && year < 10_000,
            "Timestamp is out of range [0001-01-01T00:00:00Z 9999-12-31T23:59:59.999999999Z]");
    }
}

unittest
{
    import std.algorithm.comparison : equal;
    import std.array : array, empty;
    import std.datetime : DateTime, msecs, seconds, UTC;

    static const epoch = SysTime(DateTime(1970, 1, 1), UTC());

    assert(equal(Timestamp(epoch + 5.seconds + 5.msecs).toProtobuf, [
        0x08, 0x05, 0x10, 0xc0, 0x96, 0xb1, 0x02]));
    assert(equal(Timestamp(epoch + 5.msecs).toProtobuf, [
        0x10, 0xc0, 0x96, 0xb1, 0x02]));
    assert(equal(Timestamp(epoch + (-5).msecs).toProtobuf, [
        0x10, 0xc0, 0xe9, 0xce, 0xfd, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01]));
    assert(equal(Timestamp(epoch + (-5).seconds + (-5).msecs).toProtobuf, [
        0x08, 0xfb, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01,
        0x10, 0xc0, 0xe9, 0xce, 0xfd, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01]));

    auto buffer = Timestamp(epoch + 5.seconds + 5.msecs).toProtobuf.array;
    assert(buffer.fromProtobuf!Timestamp == Timestamp(epoch + 5.seconds + 5.msecs));
    buffer = Timestamp(epoch + 5.msecs).toProtobuf.array;
    assert(buffer.fromProtobuf!Timestamp == Timestamp(epoch + 5.msecs));
    buffer = Timestamp(epoch + (-5).msecs).toProtobuf.array;
    assert(buffer.fromProtobuf!Timestamp == Timestamp(epoch + (-5).msecs));
    buffer = Timestamp(epoch + (-5).seconds + (-5).msecs).toProtobuf.array;
    assert(buffer.fromProtobuf!Timestamp == Timestamp(epoch + (-5).seconds + (-5).msecs));

    buffer = Timestamp(epoch).toProtobuf.array;
    assert(buffer.empty);
    assert(buffer.fromProtobuf!Timestamp == epoch);
}

unittest
{
    import std.datetime : DateTime, hours, minutes, msecs, nsecs, seconds, SimpleTimeZone, UTC;
    import std.exception : assertThrown;
    import std.json : JSONValue;

    static const epoch = SysTime(DateTime(1970, 1, 1), UTC());

    assert(protoDefaultValue!Timestamp == epoch);

    assert(Timestamp(epoch).toJSONValue == JSONValue("1970-01-01T00:00:00Z"));
    assert(Timestamp(epoch + 5.seconds).toJSONValue == JSONValue("1970-01-01T00:00:05Z"));
    assert(Timestamp(epoch + 5.seconds + 50.msecs).toJSONValue == JSONValue("1970-01-01T00:00:05.050Z"));
    assert(Timestamp(epoch + 5.seconds + 300.nsecs).toJSONValue == JSONValue("1970-01-01T00:00:05.000000300Z"));

    immutable nonUTCTimeZone = new SimpleTimeZone(-3600.seconds);
    static const nonUTCTimestamp = SysTime(DateTime(1970, 1, 1), nonUTCTimeZone);
    assert(Timestamp(nonUTCTimestamp).toJSONValue == JSONValue("1970-01-01T01:00:00Z"));

    static const tooSmall = SysTime(DateTime(0, 12, 31), UTC());
    assertThrown!ProtobufException(Timestamp(tooSmall).toJSONValue);
    static const tooLarge = SysTime(DateTime(10_000, 1, 1), UTC());
    assertThrown!ProtobufException(Timestamp(tooLarge).toJSONValue);

    assert(epoch == JSONValue("1970-01-01T00:00:00Z").fromJSONValue!Timestamp);
    assert(epoch + 5.seconds == JSONValue("1970-01-01T00:00:05Z").fromJSONValue!Timestamp);
    assert(epoch + 5.seconds + 50.msecs == JSONValue("1970-01-01T00:00:05.050Z").fromJSONValue!Timestamp);
    assert(epoch + 5.seconds + 300.nsecs == JSONValue("1970-01-01T00:00:05.000000300Z").fromJSONValue!Timestamp);

    assert(epoch + 2.hours == JSONValue("1970-01-01T00:00:00-02:00").fromJSONValue!Timestamp);
    assert(epoch - 2.hours - 30.minutes == JSONValue("1970-01-01T00:00:00+02:30").fromJSONValue!Timestamp);
    assert(epoch + 5.seconds + 50.msecs + 2.hours ==
        JSONValue("1970-01-01T00:00:05.050-02:00").fromJSONValue!Timestamp);
    assert(epoch + 5.seconds + 50.msecs - 2.hours - 30.minutes ==
        JSONValue("1970-01-01T00:00:05.050+02:30").fromJSONValue!Timestamp);
    assert(epoch + 5.seconds + 300.nsecs + 2.hours ==
        JSONValue("1970-01-01T00:00:05.000000300-02:00").fromJSONValue!Timestamp);
    assert(epoch + 5.seconds + 300.nsecs - 2.hours - 30.minutes ==
        JSONValue("1970-01-01T00:00:05.000000300+02:30").fromJSONValue!Timestamp);
}
