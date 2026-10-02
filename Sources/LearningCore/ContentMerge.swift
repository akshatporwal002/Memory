import Foundation

public struct ContentMergeResult: Sendable {
    public let merged: Data?
    public let conflictingPaths: [String]
}
/// Three-way object merging. Notebook arrays are keyed by stable IDs; order changes are structural conflicts.
public enum ContentMerge {
    public static func merge(base: Data,yours: Data,theirs: Data) throws -> ContentMergeResult {
        let b = try JSONSerialization.jsonObject(with:base,options:.fragmentsAllowed)
        let y = try JSONSerialization.jsonObject(with:yours,options:.fragmentsAllowed)
        let t = try JSONSerialization.jsonObject(with:theirs,options:.fragmentsAllowed)
        var conflicts: [String] = []
        let value = merge(b,y,t,path:"",conflicts:&conflicts)
        return ContentMergeResult(merged:conflicts.isEmpty ? try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.fragmentsAllowed]) : nil,conflictingPaths:conflicts)
    }
    private static func equal(_ a: Any,_ b: Any) -> Bool { (a as? NSObject)?.isEqual(b) ?? false }
    private static func merge(_ b: Any,_ y: Any,_ t: Any,path: String,conflicts: inout [String]) -> Any {
        if equal(y,t) { return y }; if equal(y,b) { return t }; if equal(t,b) { return y }
        if let bd = b as? [String:Any],let yd = y as? [String:Any],let td = t as? [String:Any] {
            // A deletion opposed to edits must not disappear into independent field merging.
            if (yd["deleted"] as? Bool == true) != (td["deleted"] as? Bool == true), bd["deleted"] as? Bool != true {
                conflicts.append(path + "/deleted"); return y
            }
            var result: [String:Any] = [:]
            for key in Set(bd.keys).union(yd.keys).union(td.keys).sorted() {
                let value = merge(bd[key] ?? NSNull(),yd[key] ?? NSNull(),td[key] ?? NSNull(),path:path + "/" + key,conflicts:&conflicts)
                if !(value is NSNull) { result[key] = value }
            }
            return result
        }
        if let ba = b as? [[String:Any]],let ya = y as? [[String:Any]],let ta = t as? [[String:Any]],
           ba.allSatisfy({ $0["id"] is String }),ya.allSatisfy({ $0["id"] is String }),ta.allSatisfy({ $0["id"] is String }) {
            let ids: ([[String:Any]]) -> [String] = { $0.compactMap { $0["id"] as? String } }
            let bi = ids(ba),yi = ids(ya),ti = ids(ta)
            guard Set(yi).count == yi.count,Set(ti).count == ti.count,Set(bi).count == bi.count else { conflicts.append(path); return y }
            let order: [String]
            if yi == ti { order = yi } else if yi == bi { order = ti } else if ti == bi { order = yi }
            else { conflicts.append(path + "/order"); return y }
            let bd = Dictionary(uniqueKeysWithValues:zip(bi,ba)),yd = Dictionary(uniqueKeysWithValues:zip(yi,ya)),td = Dictionary(uniqueKeysWithValues:zip(ti,ta))
            var result: [[String:Any]] = []
            for id in Set(bi).union(yi).union(ti).sorted() {
                let value = merge(bd[id] ?? NSNull(),yd[id] ?? NSNull(),td[id] ?? NSNull(),path:path + "/" + id,conflicts:&conflicts)
                if let value = value as? [String:Any] { result.append(value) }
            }
            return order.compactMap { id in result.first { $0["id"] as? String == id } }
        }
        conflicts.append(path.isEmpty ? "/" : path); return y
    }
}
