module.exports = {
    startAsync: function (success, fail, args) {
        try {
            var uri = new Windows.Foundation.Uri(args[0]),
                resultFilePath = args[1],
                /**
                 * A custom user agent. The default Edge user agent will be used if not specified.
                 * @type {string}
                 */
                userAgent = args[5],
                /**
                 * The download operation.
                 * @type {Windows.Networking.BackgroundTransfer.DownloadOperation}
                 **/
                operation,
                downloadLocation;

            var downloadPromise = Windows.Storage.StorageFile.getFileFromApplicationUriAsync(new Windows.Foundation.Uri(resultFilePath))
                .then(function (file) {
                    downloadLocation = file;
                }, fail)
                .then(function () {
                    return Windows.Networking.BackgroundTransfer.BackgroundDownloader.getCurrentDownloadsAsync();
                }, fail)
                .then(function (downloads) {
                    // After app termination, an app should enumerate all existing DownloadOperation instances at next
                    // start-up using GetCurrentDownloadsAsync. When a Windows Store app using Background Transfer is
                    // terminated, incomplete downloads will persist in the background. If the app is restarted after
                    // termination and operations from the previous session are not enumerated and re-attached to the
                    // current session, they will remain incomplete and continue to occupy resources
                    // http://msdn.microsoft.com/library/windows/apps/br207126
                    for (var i = 0; i < downloads.size; i++) {
                        if (downloads[i].requestedUri.absoluteUri == uri.absoluteUri) {
                            // resume download
                            return downloads[i].attachAsync();
                        }
                    }

                    var downloader = new Windows.Networking.BackgroundTransfer.BackgroundDownloader();

                    // Check if a user agent is supplied and set it on the request if it is
                    if (userAgent) {
                        downloader.setRequestHeader("user-agent", userAgent);
                    }

                    // new download
                    operation = downloader.createDownload(uri, downloadLocation);
                    return operation.startAsync();
                }, fail);

            // attach callbacks
            downloadPromise.then(function () {
                success();
            }, function () {
                fail(operation.getResponseInformation());
            }, function (operation) {
                var progress = {
                    bytesReceived: operation.progress.bytesReceived,
                    totalBytesToReceive: operation.progress.totalBytesToReceive
                };

                success({
                    progress: progress
                }, {
                    keepCallback: true
                });
            });
            // save operation promise to be able to stop it later
            BackgroundTransfer.activeDownloads = BackgroundTransfer.activeDownloads || [];
            BackgroundTransfer.activeDownloads[uri.absoluteUri] = downloadPromise;

        } catch (ex) {
            fail(ex);
        }

    },
    stop: function (success, fail, args) {
        try {
            var uri = new Windows.Foundation.Uri(args[0]);

            if (BackgroundTransfer.activeDownloads && BackgroundTransfer.activeDownloads[uri.absoluteUri]) {
                BackgroundTransfer.activeDownloads[uri.absoluteUri].cancel();
                BackgroundTransfer.activeDownloads[uri.absoluteUri] = null;
            }

            success();

        } catch (ex) {
            fail(ex);
        }
    }
};
require("cordova/exec/proxy").add("BackgroundDownload", module.exports);
