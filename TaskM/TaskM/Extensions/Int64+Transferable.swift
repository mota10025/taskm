import CoreTransferable
import UniformTypeIdentifiers

extension Int64: @retroactive Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .plainText)
    }
}
