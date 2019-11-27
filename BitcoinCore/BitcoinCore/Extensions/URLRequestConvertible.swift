import Alamofire

extension URLRequestConvertible {

    var description: String {
        return "\(urlRequest?.httpMethod ?? "") \(urlRequest?.url?.absoluteString ?? "")"
    }

}
