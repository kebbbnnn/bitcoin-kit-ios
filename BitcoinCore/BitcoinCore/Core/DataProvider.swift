import Foundation
import HSHDWalletKit
import RxSwift
import BigInt
import HSCryptoKit

class DataProvider {
    private let disposeBag = DisposeBag()

    private let storage: IStorage
    private let balanceProvider: IBalanceProvider
    private let transactionInfoConverter: ITransactionInfoConverter

    private let balanceUpdateSubject = PublishSubject<Void>()

    public var balance: BalanceInfo {
        didSet {
            if !(oldValue == balance) {
                delegate?.balanceUpdated(balance: balance)
            }
        }
    }
    public var lastBlockInfo: BlockInfo? = nil

    weak var delegate: IDataProviderDelegate?

    init(storage: IStorage, balanceProvider: IBalanceProvider, transactionInfoConverter: ITransactionInfoConverter, throttleTimeMilliseconds: Int = 500) {
        self.storage = storage
        self.balanceProvider = balanceProvider
        self.transactionInfoConverter = transactionInfoConverter
        self.balance = balanceProvider.balanceInfo
        self.lastBlockInfo = storage.lastBlock.map { blockInfo(fromBlock: $0) }

        balanceUpdateSubject.throttle(DispatchTimeInterval.milliseconds(throttleTimeMilliseconds), scheduler: ConcurrentDispatchQueueScheduler(qos: .background)).subscribe(onNext: { [weak self] in
            self?.balance = balanceProvider.balanceInfo
        }).disposed(by: disposeBag)
    }

    private func blockInfo(fromBlock block: Block) -> BlockInfo {
        return BlockInfo(
                headerHash: block.headerHash.reversedHex,
                height: block.height,
                timestamp: block.timestamp
        )
    }

}

extension DataProvider: IBlockchainDataListener {

    func onUpdate(updated: [Transaction], inserted: [Transaction], inBlock block: Block?) {
        var blocks = [Block]()

        if let block = block {
            blocks.append(block)
        }

        delegate?.transactionsUpdated(
                inserted: storage.fullInfo(forTransactions: inserted.map { TransactionWithBlock(transaction: $0, blockHeight: block?.height) }).map { transactionInfoConverter.transactionInfo(fromTransaction: $0) },
                updated: storage.fullInfo(forTransactions: updated.map { TransactionWithBlock(transaction: $0, blockHeight: block?.height) }).map { transactionInfoConverter.transactionInfo(fromTransaction: $0) }
        )

        balanceUpdateSubject.onNext(())
    }

    func onDelete(transactionHashes: [String]) {
        delegate?.transactionsDeleted(hashes: transactionHashes)

        balanceUpdateSubject.onNext(())
    }

    func onInsert(block: Block) {
        if block.height > (lastBlockInfo?.height ?? 0) {
            let lastBlockInfo = blockInfo(fromBlock: block)
            self.lastBlockInfo = lastBlockInfo
            delegate?.lastBlockInfoUpdated(lastBlockInfo: lastBlockInfo)

            balanceUpdateSubject.onNext(())
        }
    }

}

extension DataProvider: IDataProvider {

    func transactions(fromHash: String?, limit: Int?) -> Single<[TransactionInfo]> {
        return Single.create { observer in
            var fromTimestamp: Int? = nil
            var fromOrder: Int? = nil

            if let fromHash = fromHash, let fromHashData = Data(hex: fromHash), let fromTransaction = self.storage.transaction(byHash: Data(fromHashData.reversed())) {
                fromTimestamp = fromTransaction.timestamp
                fromOrder = fromTransaction.order
            }

            let transactions = self.storage.fullTransactionsInfo(fromTimestamp: fromTimestamp, fromOrder: fromOrder, limit: limit)

            observer(.success(transactions.map() { self.transactionInfoConverter.transactionInfo(fromTransaction: $0) }))
            return Disposables.create()
        }
    }

    func debugInfo(network: INetwork, scriptType: ScriptType, addressConverter: IAddressConverter) -> String {
        var lines = [String]()

        let pubKeys = storage.publicKeys().sorted(by: { $0.index < $1.index })

        for pubKey in pubKeys {
            lines.append("acc: \(pubKey.account) - inx: \(pubKey.index) - ext: \(pubKey.external) : \((try! addressConverter.convert(keyHash: pubKey.keyHash, type: scriptType)).stringValue)")
        }
        lines.append("PUBLIC KEYS COUNT: \(pubKeys.count)")
        return lines.joined(separator: "\n")
    }

}
