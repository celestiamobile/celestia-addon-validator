# Upload Celestia Add-ons

## Login with a GitHub Account

Go to the [Update Addon](https://celestia.mobi/submit-addon) page and login with your GitHub account.

If you are uploading an add-on that exceeds 50MB, you also need to login with an Apple ID.

## Fill in Information

Fill in the information about this add-on you are adding, changing, or removing.

## Submitting Add-ons

After clicking the `Submit` button, two pop-up windows will appear. On its first pop-up, simply enter the title of the addon you submitted

![image](https://github.com/celestiamobile/celestia-addon-validator/assets/95486841/7f720084-b43d-46d1-9714-0b67e88e447c)

The second pop-up window is optional. State the changes you made on the addon's update on this window. Simply click `OK` if it is an entirely new addon submitted

![image](https://github.com/celestiamobile/celestia-addon-validator/assets/95486841/36874e29-44f9-41bc-b69f-b8c481e05437)

The page will then automatically create a PR for you once the two pop-up windows are successfully filled up.

![image](https://github.com/celestiamobile/celestia-addon-validator/assets/95486841/d2a16b23-7f8f-488d-accf-6b51479330ef)

## Check Validation Result

Validation should only take a few minutes.

If validation fails, it will appear like this.

![failing vaidation](images/failing-validation.png)

Click `Details`, and see where it goes wrong.

![failing vaidation details](images/validation-details.png)

In this example, `title` is missing in submitting a new add-on. If it fails, Click `Close pull request` and start from the beginning.

In a successful validation, a summary will be displayed in details.

![successful vaidation details](images/successful-validation.png)

## Upload to celestia.mobi

After it passes validation, a collaborator can merge this pull request. After the pull request is merged, more checks will be performed automatically and the add-on will be uploaded to celestia.mobi.

It may take up to about an hour after the pull request is merged for users to see the changes on celestia.mobi.
