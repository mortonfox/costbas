# costbas - Calculate cost basis from Quicken QIF data

## Introduction

costbas.rb is a Ruby script that reads QIF files from Quicken and produces a report showing share lots after each transaction and the cost basis for each stock or mutual fund sale transaction. It calculates the cost basis using two methods, FIFO and average cost basis, and cost basis figures are separated into short-term and long-term for your Schedule D filling convenience.

## QIF file

Use the following steps to export a QIF file from Quicken:
* Select File, File Export, QIF File in the menu.
* In the dialog box, select the account you wish to export.
* The default date range should already cover your entire account history, so don't change that.
* Under "Include in Export", select only "Transactions" and leave the rest unchecked.
* Click on OK.

## Running costbas

Run the following command to generate a report to stdout:

    ruby costbas.rb qdata.QIF
    
where qdata.QIF is the name of the QIF file you exported.
