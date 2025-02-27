//
//  SwiftyBeaver.swift
//  SwiftyBeaver
//
//  Created by Sebastian Kreutzberger (Twitter @skreutzb) on 28.11.15.
//  Copyright © 2015 Sebastian Kreutzberger
//  Some rights reserved: http://opensource.org/licenses/MIT
//

import Foundation

open class SwiftyBeaver {

    /// version string of framework
    public static let version = "1.9.4"  // UPDATE ON RELEASE!
    /// build number of framework
    public static let build = 1950 // version 1.6.2 -> 1620, UPDATE ON RELEASE!

    public enum Level: Int {
        case verbose = 0
        case debug = 1
        case info = 2
        case warning = 3
        case error = 4
    }

    // a set of active destinations
    public private(set) static var destinations = Set<BaseDestination>()

    // MARK: Destination Handling

    /// returns boolean about success
    @discardableResult
    open class func addDestination(_ destination: BaseDestination) -> Bool {
        if destinations.contains(destination) {
            return false
        }
        
        // Check for duplicate deetinations with the same label.
        for dest in destinations {
            if let label = dest.label, label == destination.label {
                return false
            }
        }
        
        destinations.insert(destination)
        return true
    }

    /// returns boolean about success
    @discardableResult
    open class func removeDestination(_ destination: BaseDestination) -> Bool {
        if destinations.contains(destination) == false {
            return false
        }
        destinations.remove(destination)
        return true
    }

    /// if you need to start fresh
    open class func removeAllDestinations() {
        destinations.removeAll()
    }

    /// returns the amount of destinations
    open class func countDestinations() -> Int {
        return destinations.count
    }

    /// returns the current thread name
    open class func threadName() -> String {

        #if os(Linux)
            // on 9/30/2016 not yet implemented in server-side Swift:
            // > import Foundation
            // > Thread.isMainThread
            return ""
        #else
            if Thread.isMainThread {
                return ""
            } else {
                let name = __dispatch_queue_get_label(nil)
                return String(cString: name, encoding: .utf8) ?? Thread.current.description
            }
        #endif
    }

    // MARK: Levels

    /// log something generally unimportant (lowest priority)
    open class func verbose(dest: String? = nil, _ message: @autoclosure () -> Any, _
        file: String = #file, _ function: String = #function, line: Int = #line, context: Any? = nil) {
        #if swift(>=5)
        custom(dest: dest, level: .verbose, message: message(), file: file, function: function, line: line, context: context)
        #else
        custom(dest: dest, level: .verbose, message: message, file: file, function: function, line: line, context: context)
        #endif
    }

    /// log something which help during debugging (low priority)
    open class func debug(dest: String? = nil, _ message: @autoclosure () -> Any, _
        file: String = #file, _ function: String = #function, line: Int = #line, context: Any? = nil) {

        #if swift(>=5)
        custom(dest: dest, level: .debug, message: message(), file: file, function: function, line: line, context: context)
        #else
        custom(dest: dest, level: .debug, message: message, file: file, function: function, line: line, context: context)
        #endif
    }

    /// log something which you are really interested but which is not an issue or error (normal priority)
    open class func info(dest: String? = nil, _ message: @autoclosure () -> Any, _
        file: String = #file, _ function: String = #function, line: Int = #line, context: Any? = nil) {
        #if swift(>=5)
        custom(dest: dest, level: .info, message: message(), file: file, function: function, line: line, context: context)
        #else
        custom(dest: dest, level: .info, message: message, file: file, function: function, line: line, context: context)
        #endif
    }

    /// log something which may cause big trouble soon (high priority)
    open class func warning(dest: String? = nil, _ message: @autoclosure () -> Any, _
        file: String = #file, _ function: String = #function, line: Int = #line, context: Any? = nil) {

        #if swift(>=5)
        custom(dest: dest, level: .warning, message: message(), file: file, function: function, line: line, context: context)
        #else
        custom(dest: dest, level: .warning, message: message, file: file, function: function, line: line, context: context)
        #endif
    }

    /// log something which will keep you awake at night (highest priority)
    open class func error(dest: String? = nil, _ message: @autoclosure () -> Any, _
        file: String = #file, _ function: String = #function, line: Int = #line, context: Any? = nil) {
        #if swift(>=5)
        custom(dest: dest, level: .error, message: message(), file: file, function: function, line: line, context: context)
        #else
        custom(dest: dest, level: .error, message: message, file: file, function: function, line: line, context: context)
        #endif
    }

    /// custom logging to manually adjust values, should just be used by other frameworks
    open class func custom(dest: String? = nil, level: SwiftyBeaver.Level, message: @autoclosure () -> Any,
                             file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        #if swift(>=5)
        dispatch_send(destination: dest, level: level, message: message(), thread: threadName(),
                      file: file, function: function, line: line, context: context)
        #else
        dispatch_send(destination: dest, level: level, message: message, thread: threadName(),
                      file: file, function: function, line: line, context: context)
        #endif
    }

    /// internal helper which dispatches send to dedicated queue if minLevel is ok
    class func dispatch_send(destination: String?, level: SwiftyBeaver.Level, message: @autoclosure () -> Any,
        thread: String, file: String, function: String, line: Int, context: Any?) {
        var resolvedMessage: String?
        for dest in destinations {
            if !dest.isMatch(destination) {
                continue
            }
            
            guard let queue = dest.queue else {
                continue
            }

            resolvedMessage = resolvedMessage == nil && dest.hasMessageFilters() ? "\(message())" : resolvedMessage
            if dest.shouldLevelBeLogged(level, path: file, function: function, message: resolvedMessage) {
                // try to convert msg object to String and put it on queue
                let msgStr = resolvedMessage == nil ? "\(message())" : resolvedMessage!
                let f = stripParams(function: function)

                if dest.asynchronously {
                    queue.async {
                        _ = dest.send(level, msg: msgStr, thread: thread, file: file, function: f, line: line, context: context)
                    }
                } else {
                    queue.sync {
                        _ = dest.send(level, msg: msgStr, thread: thread, file: file, function: f, line: line, context: context)
                    }
                }
            }
        }
    }

    /**
     DEPRECATED & NEEDS COMPLETE REWRITE DUE TO SWIFT 3 AND GENERAL INCORRECT LOGIC
     Flush all destinations to make sure all logging messages have been written out
     Returns after all messages flushed or timeout seconds

     - returns: true if all messages flushed, false if timeout or error occurred
     */
    public class func flush(secondTimeout: Int64) -> Bool {

        /*
        guard let grp = dispatch_group_create() else { return false }
        for dest in destinations {
            if let queue = dest.queue {
                dispatch_group_enter(grp)
                queue.asynchronously(execute: {
                    dest.flush()
                    grp.leave()
                })
            }
        }
        let waitUntil = DispatchTime.now(dispatch_time_t(DISPATCH_TIME_NOW), secondTimeout * 1000000000)
        return dispatch_group_wait(grp, waitUntil) == 0
         */
        return true
    }

    /// removes the parameters from a function because it looks weird with a single param
    class func stripParams(function: String) -> String {
        var f = function
        if let indexOfBrace = f.find("(") {
            #if swift(>=4.0)
            f = String(f[..<indexOfBrace])
            #else
            f = f.substring(to: indexOfBrace)
            #endif
        }
        f += "()"
        return f
    }
}
