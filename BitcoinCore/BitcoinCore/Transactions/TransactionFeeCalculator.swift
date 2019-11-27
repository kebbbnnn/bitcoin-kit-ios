class TransactionFeeCalculator {

    private let outputSetter: IOutputSetter
    private let inputSetter: IInputSetter
    private let addressConverter: IAddressConverter
    private let publicKeyManager: IPublicKeyManager
    private let changeScriptType: ScriptType

    init(outputSetter: IOutputSetter, inputSetter: IInputSetter, addressConverter: IAddressConverter, publicKeyManager: IPublicKeyManager, changeScriptType: ScriptType) {
        self.outputSetter = outputSetter
        self.inputSetter = inputSetter
        self.addressConverter = addressConverter
        self.publicKeyManager = publicKeyManager
        self.changeScriptType = changeScriptType
    }

    private func sampleAddress() throws -> String {
        return try addressConverter.convert(publicKey: try publicKeyManager.changePublicKey(), type: changeScriptType).stringValue
    }
}

extension TransactionFeeCalculator: ITransactionFeeCalculator {

    func fee(for value: Int, feeRate: Int, senderPay: Bool, toAddress: String?, pluginData: [UInt8: IPluginData] = [:]) throws -> Int {
        let mutableTransaction = MutableTransaction()

        try outputSetter.setOutputs(to: mutableTransaction, toAddress: toAddress ?? (try sampleAddress()), value: value, pluginData: pluginData)
        try inputSetter.setInputs(to: mutableTransaction, feeRate: feeRate, senderPay: senderPay)

        let inputsTotalValue = mutableTransaction.inputsToSign.reduce(0) { total, input in total + input.previousOutput.value }
        let outputsTotalValue = mutableTransaction.recipientValue + mutableTransaction.changeValue

        return inputsTotalValue - outputsTotalValue
    }

}
